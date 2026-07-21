[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [switch]$MergeConfirmed,
    [ValidateRange(120, 1800)][int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$scriptedInputRunner = Join-Path $PSScriptRoot 'run-p0-dfl-with-scripted-input.py'
$validatorScript = Join-Path $PSScriptRoot 'validate-p0-merge-output.py'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$modelClass = 'SAEHD'
$modelBaseName = 'p0gate'
$modelPrefix = $modelBaseName + '_' + $modelClass
$expectedIteration = 4

function Get-ProfileValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $profile.ContainsKey($Name)) { throw "Missing profile key: $Name" }
    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Empty profile value: $Name" }
    return $value
}

function Get-PropertyValue {
    param([AllowNull()]$Object, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Normalize-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )
    $candidateFull = Normalize-FullPath -Path $Candidate
    $parentFull = Normalize-FullPath -Path $Parent
    if ($candidateFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidateFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $items = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
    $files = @($items | Where-Object { -not $_.PSIsContainer })
    $directories = @($items | Where-Object { $_.PSIsContainer })
    $builder = New-Object System.Text.StringBuilder
    foreach ($item in $items) {
        $relative = $item.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
        if ($item.PSIsContainer) {
            $kind = 'D'
            $length = [int64]0
        }
        else {
            $kind = 'F'
            $length = [int64]$item.Length
        }
        [void]$builder.Append($kind).Append('|').Append($relative).Append('|').Append($length).Append('|').Append($item.LastWriteTimeUtc.Ticks).Append("`n")
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        $hash = ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
    $totalBytes = [int64]0
    foreach ($file in $files) { $totalBytes += [int64]$file.Length }
    return [ordered]@{
        path = $Path
        file_count = $files.Count
        directory_count = $directories.Count
        total_bytes = $totalBytes
        metadata_sha256 = $hash
    }
}

function Get-FileInventory {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $records = New-Object System.Collections.ArrayList
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Force -ErrorAction Stop | Sort-Object Name)) {
        [void]$records.Add([ordered]@{
            path = $file.FullName
            name = $file.Name
            size_bytes = [int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        })
    }
    return @($records | ForEach-Object { $_ })
}

function Confirm-InventoryUnchanged {
    param([Parameter(Mandatory = $true)]$Records)
    foreach ($record in @($Records)) {
        if (-not (Test-Path -LiteralPath $record.path -PathType Leaf)) { return $false }
        $item = Get-Item -LiteralPath $record.path -Force -ErrorAction Stop
        if ([int64]$item.Length -ne [int64]$record.size_bytes) { return $false }
        $hash = (Get-FileHash -LiteralPath $record.path -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($hash -ne [string]$record.sha256) { return $false }
    }
    return $true
}

function Quote-NativeArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
}

function Limit-Text {
    param([AllowNull()][AllowEmptyString()][string]$Text, [int]$MaximumCharacters = 30000)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $MaximumCharacters) { return $Text }
    return $Text.Substring($Text.Length - $MaximumCharacters) + "`n...[tail retained]"
}

function Invoke-IsolatedPython {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$ProcessTimeoutSeconds
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $pythonExe
    $quotedArguments = @($Arguments | ForEach-Object { Quote-NativeArgument -Value ([string]$_) })
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.WorkingDirectory = $deepFaceLabRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['PATH'] = $isolatedPath

    foreach ($name in @('PYTHONHOME', 'PYTHONPATH', 'CUDA_PATH', 'CUDA_HOME', 'CUDNN_PATH', 'CUDA_VISIBLE_DEVICES')) {
        $startInfo.EnvironmentVariables.Remove($name)
    }
    $startInfo.EnvironmentVariables['PYTHONNOUSERSITE'] = '1'
    $startInfo.EnvironmentVariables['PYTHONUNBUFFERED'] = '1'
    $startInfo.EnvironmentVariables['TF_FORCE_GPU_ALLOW_GROWTH'] = 'true'
    $startInfo.EnvironmentVariables['TF_CPP_MIN_LOG_LEVEL'] = '0'
    $startInfo.EnvironmentVariables['TF_ENABLE_ONEDNN_OPTS'] = '0'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    $timedOut = $false
    $stdout = ''
    $stderr = ''
    $exitCode = $null

    try {
        $started = $process.Start()
        if (-not $started) { throw ("Process did not start: {0}" -f $Label) }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        try { $process.StandardInput.Close() } catch {}

        $startedAt = Get-Date
        $nextProgress = 10
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            $process.Refresh()
            $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
            if ($elapsed -ge $nextProgress) {
                Write-Host ("  {0}: elapsed {1}s / timeout {2}s" -f $Label, $elapsed, $ProcessTimeoutSeconds) -ForegroundColor DarkCyan
                $nextProgress += 10
            }
            if ($elapsed -ge $ProcessTimeoutSeconds) {
                $timedOut = $true
                Write-Host ("  {0}: timeout reached; stopping the process tree." -f $Label) -ForegroundColor Yellow
                Stop-ProcessTree -ProcessId $process.Id
                break
            }
        }

        try { $process.WaitForExit() } catch {}
        try { $stdout = [string]$stdoutTask.Result } catch { $stdout = '' }
        try { $stderr = [string]$stderrTask.Result } catch { $stderr = $_.Exception.ToString() }
        if (-not $timedOut) {
            try { $exitCode = [int]$process.ExitCode } catch { $exitCode = $null }
        }
    }
    catch {
        $stderr = $_.Exception.ToString()
    }
    finally {
        if ($started) {
            try {
                $process.Refresh()
                if (-not $process.HasExited) { Stop-ProcessTree -ProcessId $process.Id }
            }
            catch {}
        }
        $process.Dispose()
    }

    return [ordered]@{
        label = $Label
        timed_out = $timedOut
        exit_code = $exitCode
        stdout = $stdout
        stderr = $stderr
    }
}

function Convert-SentinelJson {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$BeginMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker
    )
    $pattern = '(?s)' + [regex]::Escape($BeginMarker) + '\s*(.*?)\s*' + [regex]::Escape($EndMarker)
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return [ordered]@{ value = $null; error = 'Sentinel JSON markers were not found.' }
    }
    try {
        return [ordered]@{ value = ($match.Groups[1].Value | ConvertFrom-Json); error = $null }
    }
    catch {
        return [ordered]@{ value = $null; error = $_.Exception.Message }
    }
}

if (-not $MergeConfirmed) {
    throw 'Step 16 requires explicit confirmation to merge the accepted P0 checkpoint.'
}
foreach ($requiredFile in @($scriptedInputRunner, $validatorScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Required step-16 file was not found: $requiredFile" }
}

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$runtimeRoot = Normalize-FullPath -Path (Get-ProfileValue 'RuntimeRoot')
$pythonExe = Normalize-FullPath -Path (Get-ProfileValue 'PythonExe')
$deepFaceLabRoot = Normalize-FullPath -Path (Get-ProfileValue 'DeepFaceLabRoot')
$mainPy = Normalize-FullPath -Path (Get-ProfileValue 'MainPy')
$defaultWorkspace = Normalize-FullPath -Path (Get-ProfileValue 'WorkspacePath')
$workspaceResolved = Normalize-FullPath -Path (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$repoRootNormalized = Normalize-FullPath -Path $repoRoot

foreach ($requiredPath in @($runtimeRoot, $pythonExe, $deepFaceLabRoot, $mainPy, $defaultWorkspace, $workspaceResolved)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required path does not exist: $requiredPath" }
}
if (Test-PathInside -Candidate $workspaceResolved -Parent $repoRootNormalized) { throw 'The isolated P0 workspace must remain outside the Git repository.' }
if (Test-PathInside -Candidate $workspaceResolved -Parent $runtimeRoot) { throw 'The isolated P0 workspace must remain outside the historical runtime.' }

$resumeMarkerPath = Join-Path $workspaceResolved 'p0-resume-training-manifest.json'
if (-not (Test-Path -LiteralPath $resumeMarkerPath -PathType Leaf)) { throw 'The accepted step-15 workspace marker is missing.' }
$resumeMarker = Get-Content -LiteralPath $resumeMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string](Get-PropertyValue -Object $resumeMarker -Name 'status' -Default '') -ne 'passed') { throw 'The step-15 marker is not passed.' }
if ([string](Get-PropertyValue -Object $resumeMarker -Name 'model_prefix' -Default '') -ne $modelPrefix) { throw 'The step-15 model prefix does not match.' }
if ([int](Get-PropertyValue -Object $resumeMarker -Name 'after_iteration' -Default -1) -ne $expectedIteration) { throw 'The step-15 marker iteration is not 4.' }

$destinationInput = Join-Path $workspaceResolved 'data_dst'
$destinationAligned = Join-Path $workspaceResolved 'data_dst\aligned'
$modelDirectory = Join-Path $workspaceResolved 'model'
$mergedDirectory = Join-Path $workspaceResolved 'merged'
$maskDirectory = Join-Path $workspaceResolved 'merged_mask'
foreach ($directory in @($destinationInput, $destinationAligned, $modelDirectory, $mergedDirectory, $maskDirectory)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Required workspace directory is missing: $directory" }
}
if (@(Get-ChildItem -LiteralPath $mergedDirectory -Force -ErrorAction Stop).Count -ne 0) { throw 'The final merged directory must be empty before step 16.' }
if (@(Get-ChildItem -LiteralPath $maskDirectory -Force -ErrorAction Stop).Count -ne 0) { throw 'The final merged-mask directory must be empty before step 16.' }
if (@(Get-ChildItem -LiteralPath $destinationInput -File -Force -ErrorAction Stop).Count -ne 3) { throw 'Step 16 expects exactly three destination input images.' }
if (@(Get-ChildItem -LiteralPath $destinationAligned -File -Force -ErrorAction Stop).Count -ne 3) { throw 'Step 16 expects exactly three destination aligned images.' }
if (@(Get-ChildItem -LiteralPath $modelDirectory -File -Force -ErrorAction Stop).Count -ne 8) { throw 'Step 16 expects the accepted eight-file checkpoint.' }

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) { throw 'The Git working tree is not clean.' }
$defaultWorkspaceBefore = Get-TreeSnapshot -Path $defaultWorkspace
$destinationInventory = Get-FileInventory -Directory $destinationInput
$alignedInventory = Get-FileInventory -Directory $destinationAligned
$modelInventory = Get-FileInventory -Directory $modelDirectory

$internalRoot = Join-Path $runtimeRoot '_internal'
$pythonRoot = Split-Path -Parent $pythonExe
$dllPatterns = @('cudart64*.dll','cudnn64*.dll','cublas64*.dll','cublasLt64*.dll','cufft64*.dll','curand64*.dll','cusolver64*.dll','cusparse64*.dll','nvrtc64*.dll','nvrtc-builtins64*.dll','zlibwapi.dll')
$dllFilesList = New-Object System.Collections.ArrayList
foreach ($pattern in $dllPatterns) {
    foreach ($file in @(Get-ChildItem -LiteralPath $internalRoot -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue)) { [void]$dllFilesList.Add($file) }
}
$dllFiles = @($dllFilesList | Sort-Object FullName -Unique)
$dllDirectories = @($dllFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
$candidatePaths = @($pythonRoot, (Join-Path $pythonRoot 'Scripts'), $internalRoot) + @($dllDirectories) + @((Join-Path $env:SystemRoot 'System32'), $env:SystemRoot)
$pathEntriesList = New-Object System.Collections.ArrayList
foreach ($candidate in $candidatePaths) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate) -and -not $pathEntriesList.Contains($candidate)) { [void]$pathEntriesList.Add($candidate) }
}
$pathEntries = @($pathEntriesList)
$isolatedPath = $pathEntries -join ';'

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$artifactRoot = Join-Path $repoRoot ("artifacts\p0\{0}\{1}" -f $machineId, $environmentId)
$outputDirectory = Join-Path $artifactRoot 'merge'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("p0-controlled-merge-{0}.json" -f $fileTimestamp)
$mergeStdoutPath = Join-Path $outputDirectory ($fileTimestamp + '.merge.stdout.txt')
$mergeStderrPath = Join-Path $outputDirectory ($fileTimestamp + '.merge.stderr.txt')
$validationStdoutPath = Join-Path $outputDirectory ($fileTimestamp + '.validate.stdout.txt')
$validationStderrPath = Join-Path $outputDirectory ($fileTimestamp + '.validate.stderr.txt')
$stagingMerged = Join-Path $workspaceResolved ('.merged-p0-staging-' + [Guid]::NewGuid().ToString('N'))
$stagingMask = Join-Path $workspaceResolved ('.merged-mask-p0-staging-' + [Guid]::NewGuid().ToString('N'))

$mergeProcess = $null
$validationProcess = $null
$validationParse = [ordered]@{ value = $null; error = 'Merge validation was not run.' }
$inputsUnchanged = $false
$alignedUnchanged = $false
$modelUnchanged = $false
$defaultWorkspaceUnchanged = $false
$repoUnchanged = $false
$commitSucceeded = $false
$status = 'blocked_not_started'
$fatalError = $null

Write-Host ''
Write-Host '[1/4] Verifying the accepted iteration-4 checkpoint and empty output boundary...' -ForegroundColor Cyan
Write-Host ("Profile: {0}" -f $profileResolved)
Write-Host ("Isolated workspace: {0}" -f $workspaceResolved)
Write-Host ("Destination inputs: {0}; aligned faces: {1}; model files: {2}" -f @($destinationInventory).Count, @($alignedInventory).Count, @($modelInventory).Count)
Write-Host ("Model: {0}; iteration: {1}; timeout: {2}s" -f $modelPrefix, $expectedIteration, $TimeoutSeconds)
Write-Host ("Bundled CUDA/cuDNN DLL files selected: {0}" -f $dllFiles.Count)

try {
    New-Item -ItemType Directory -Path $stagingMerged -Force | Out-Null
    New-Item -ItemType Directory -Path $stagingMask -Force | Out-Null

    $promptAnswers = @(
        'n',
        '1',
        '1',
        '0',
        '0',
        '0',
        '0',
        'rct',
        '0',
        '0',
        '0',
        '0',
        '0',
        '1'
    )
    $answersJson = $promptAnswers | ConvertTo-Json -Compress
    $answersBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($answersJson))
    $mergeArguments = @(
        $scriptedInputRunner,
        '--dfl-root', $deepFaceLabRoot,
        '--main-py', $mainPy,
        '--answers-b64', $answersBase64,
        '--',
        'merge',
        '--input-dir', $destinationInput,
        '--output-dir', $stagingMerged,
        '--output-mask-dir', $stagingMask,
        '--aligned-dir', $destinationAligned,
        '--model-dir', $modelDirectory,
        '--model', $modelClass,
        '--force-model-name', $modelBaseName,
        '--force-gpu-idxs', '0'
    )

    Write-Host ''
    Write-Host '[2/4] Running bounded non-interactive merge into temporary directories...' -ForegroundColor Cyan
    $mergeProcess = Invoke-IsolatedPython -Label 'merge' -Arguments $mergeArguments -ProcessTimeoutSeconds $TimeoutSeconds
    [System.IO.File]::WriteAllText($mergeStdoutPath, [string]$mergeProcess.stdout, $utf8Bom)
    [System.IO.File]::WriteAllText($mergeStderrPath, [string]$mergeProcess.stderr, $utf8Bom)

    $mergeCompleted = (-not $mergeProcess.timed_out) -and ($null -ne $mergeProcess.exit_code) -and ([int]$mergeProcess.exit_code -eq 0)
    if ($mergeCompleted) {
        Write-Host ''
        Write-Host '[3/4] Validating output hashes, dimensions, masks, and model iteration...' -ForegroundColor Cyan
        $validationArguments = @(
            $validatorScript,
            $destinationInput,
            $destinationAligned,
            $stagingMerged,
            $stagingMask,
            $modelDirectory,
            $modelPrefix,
            [string]$expectedIteration
        )
        $validationProcess = Invoke-IsolatedPython -Label 'merge-validation' -Arguments $validationArguments -ProcessTimeoutSeconds 120
        [System.IO.File]::WriteAllText($validationStdoutPath, [string]$validationProcess.stdout, $utf8Bom)
        [System.IO.File]::WriteAllText($validationStderrPath, [string]$validationProcess.stderr, $utf8Bom)
        $validationParse = Convert-SentinelJson -Text ([string]$validationProcess.stdout) -BeginMarker '__DFLNEXT_MERGE_VALIDATION_JSON_BEGIN__' -EndMarker '__DFLNEXT_MERGE_VALIDATION_JSON_END__'
    }
    else {
        [System.IO.File]::WriteAllText($validationStdoutPath, '', $utf8Bom)
        [System.IO.File]::WriteAllText($validationStderrPath, '', $utf8Bom)
    }

    $inputsUnchanged = Confirm-InventoryUnchanged -Records $destinationInventory
    $alignedUnchanged = Confirm-InventoryUnchanged -Records $alignedInventory
    $modelUnchanged = Confirm-InventoryUnchanged -Records $modelInventory
    $defaultWorkspaceAfter = Get-TreeSnapshot -Path $defaultWorkspace
    $defaultWorkspaceUnchanged = $defaultWorkspaceBefore.metadata_sha256 -eq $defaultWorkspaceAfter.metadata_sha256
    $repoStatusAfter = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
    $repoUnchanged = $repoStatusBefore -eq $repoStatusAfter

    $validatorPassed = $false
    if ($null -ne $validationProcess -and -not $validationProcess.timed_out -and $null -ne $validationProcess.exit_code -and [int]$validationProcess.exit_code -eq 0 -and $null -eq $validationParse.error -and $null -ne $validationParse.value) {
        $validatorPassed = [string](Get-PropertyValue -Object $validationParse.value -Name 'status' -Default '') -eq 'passed'
    }

    if ($null -eq $mergeProcess) { $status = 'blocked_merge_not_started' }
    elseif ($mergeProcess.timed_out) { $status = 'blocked_merge_timeout' }
    elseif ($null -eq $mergeProcess.exit_code -or [int]$mergeProcess.exit_code -ne 0) { $status = 'blocked_merge_process' }
    elseif (-not $validatorPassed) { $status = 'blocked_invalid_merge_output' }
    elseif (-not $inputsUnchanged) { $status = 'blocked_destination_input_changed' }
    elseif (-not $alignedUnchanged) { $status = 'blocked_destination_aligned_changed' }
    elseif (-not $modelUnchanged) { $status = 'blocked_checkpoint_changed' }
    elseif (-not $defaultWorkspaceUnchanged) { $status = 'blocked_historical_workspace_changed' }
    elseif (-not $repoUnchanged) { $status = 'blocked_repository_changed' }
    else {
        Remove-Item -LiteralPath $mergedDirectory -Recurse -Force -ErrorAction Stop
        Remove-Item -LiteralPath $maskDirectory -Recurse -Force -ErrorAction Stop
        try {
            Move-Item -LiteralPath $stagingMerged -Destination $mergedDirectory -ErrorAction Stop
            Move-Item -LiteralPath $stagingMask -Destination $maskDirectory -ErrorAction Stop
            $commitSucceeded = $true
            $status = 'passed'
        }
        catch {
            if (Test-Path -LiteralPath $mergedDirectory) { Remove-Item -LiteralPath $mergedDirectory -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $maskDirectory) { Remove-Item -LiteralPath $maskDirectory -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $mergedDirectory -Force | Out-Null
            New-Item -ItemType Directory -Path $maskDirectory -Force | Out-Null
            throw
        }
    }
}
catch {
    $fatalError = $_.Exception.ToString()
    if ($status -eq 'blocked_not_started') { $status = 'blocked_exception' }
}
finally {
    if (-not $commitSucceeded) {
        if (Test-Path -LiteralPath $stagingMerged) { Remove-Item -LiteralPath $stagingMerged -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stagingMask) { Remove-Item -LiteralPath $stagingMask -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not (Test-Path -LiteralPath $mergedDirectory)) { New-Item -ItemType Directory -Path $mergedDirectory -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $maskDirectory)) { New-Item -ItemType Directory -Path $maskDirectory -Force | Out-Null }
    }
}

$mergedInventory = @()
$maskInventory = @()
if ($commitSucceeded) {
    $mergedInventory = Get-FileInventory -Directory $mergedDirectory
    $maskInventory = Get-FileInventory -Directory $maskDirectory
}
$actualIteration = $null
$changedOutputCount = 0
$nonzeroMaskCount = 0
if ($null -ne $validationParse.value) {
    $actualIteration = Get-PropertyValue -Object $validationParse.value -Name 'actual_iteration' -Default $null
    $changedOutputCount = [int](Get-PropertyValue -Object $validationParse.value -Name 'changed_output_count' -Default 0)
    $nonzeroMaskCount = [int](Get-PropertyValue -Object $validationParse.value -Name 'nonzero_mask_count' -Default 0)
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'p0_controlled_merge_gate'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    workspace_root = $workspaceResolved
    parameters = [ordered]@{
        model_class = $modelClass
        model_prefix = $modelPrefix
        expected_iteration = $expectedIteration
        gpu_index = 0
        interactive = $false
        workers = 1
        mode = 'overlay'
        mask_mode = 'dst'
        color_transfer = 'rct'
        sharpen_mode = 0
        super_resolution_power = 0
        timeout_seconds = $TimeoutSeconds
        scripted_answer_count = 14
    }
    merge_process = if ($null -eq $mergeProcess) { $null } else { [ordered]@{
        timed_out = $mergeProcess.timed_out
        exit_code = $mergeProcess.exit_code
        stdout_file = $mergeStdoutPath
        stderr_file = $mergeStderrPath
        stdout_tail = Limit-Text -Text ([string]$mergeProcess.stdout)
        stderr_tail = Limit-Text -Text ([string]$mergeProcess.stderr)
    }}
    validation = [ordered]@{
        stdout_file = $validationStdoutPath
        stderr_file = $validationStderrPath
        parse_error = $validationParse.error
        result = $validationParse.value
    }
    outputs = [ordered]@{
        committed = $commitSucceeded
        merged_directory = $mergedDirectory
        mask_directory = $maskDirectory
        merged_files = @($mergedInventory)
        mask_files = @($maskInventory)
        changed_output_count = $changedOutputCount
        nonzero_mask_count = $nonzeroMaskCount
    }
    environment_checks = [ordered]@{
        destination_inputs_unchanged = $inputsUnchanged
        destination_aligned_unchanged = $alignedUnchanged
        checkpoint_unchanged = $modelUnchanged
        historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
        repository_unchanged = $repoUnchanged
    }
    safety = [ordered]@{
        authorized_synthetic_inputs_only = $true
        temporary_output_then_commit = $true
        partial_temporary_output_removed_on_block = -not $commitSucceeded
        model_iteration = $actualIteration
        model_modified = -not $modelUnchanged
        training_started = $false
        dfm_export_started = $false
        historical_default_workspace_modified = $false
    }
    fatal_error = $fatalError
    next_action = if ($status -eq 'passed') { 'Visually review the three merged images and masks, then implement a separate DFM export gate.' } else { 'Review merge and validation logs. Do not manually merge again or export DFM.' }
}
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 20), $utf8Bom)

if ($status -eq 'passed') {
    $workspaceMergeManifest = Join-Path $workspaceResolved 'p0-merge-manifest.json'
    $workspaceReport = [ordered]@{
        schema_version = 1
        generated_at_utc = $timestamp.ToString('o')
        status = $status
        profile_path = $profileResolved
        workspace_root = $workspaceResolved
        artifact_report = $reportPath
        model_prefix = $modelPrefix
        model_iteration = $actualIteration
        input_count = @($destinationInventory).Count
        merged_count = @($mergedInventory).Count
        mask_count = @($maskInventory).Count
        changed_output_count = $changedOutputCount
        nonzero_mask_count = $nonzeroMaskCount
        merged_directory = $mergedDirectory
        mask_directory = $maskDirectory
    }
    [System.IO.File]::WriteAllText($workspaceMergeManifest, ($workspaceReport | ConvertTo-Json -Depth 8), $utf8Bom)
}

Write-Host ''
Write-Host '[4/4] Controlled P0 merge result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Model: {0}; iteration: {1}" -f $modelPrefix, $actualIteration)
Write-Host ("Merged files: {0}; mask files: {1}" -f @($mergedInventory).Count, @($maskInventory).Count)
Write-Host ("Changed merged outputs: {0}; nonzero masks: {1}" -f $changedOutputCount, $nonzeroMaskCount)
Write-Host ("Outputs committed: {0}" -f $commitSucceeded)
Write-Host ("Destination inputs unchanged: {0}" -f $inputsUnchanged)
Write-Host ("Destination aligned unchanged: {0}" -f $alignedUnchanged)
Write-Host ("Checkpoint unchanged: {0}" -f $modelUnchanged)
Write-Host ("Historical default workspace unchanged: {0}" -f $defaultWorkspaceUnchanged)
Write-Host ("Repository unchanged: {0}" -f $repoUnchanged)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ''
Write-Host 'Safety boundary' -ForegroundColor Cyan
if ($status -eq 'passed') {
    Write-Host 'Three destination images were merged into isolated local output directories. Training and DFM export were not started.' -ForegroundColor Yellow
}
else {
    Write-Host 'Temporary merge output was blocked and removed. The accepted iteration-4 checkpoint was preserved; DFM export was not started.' -ForegroundColor Yellow
}

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    model_prefix = $modelPrefix
    model_iteration = $actualIteration
    merged_file_count = @($mergedInventory).Count
    mask_file_count = @($maskInventory).Count
    changed_output_count = $changedOutputCount
    nonzero_mask_count = $nonzeroMaskCount
    outputs_committed = $commitSucceeded
    destination_inputs_unchanged = $inputsUnchanged
    destination_aligned_unchanged = $alignedUnchanged
    checkpoint_unchanged = $modelUnchanged
    historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
    repository_unchanged = $repoUnchanged
}

if ($status -ne 'passed') { exit 1 }
exit 0
