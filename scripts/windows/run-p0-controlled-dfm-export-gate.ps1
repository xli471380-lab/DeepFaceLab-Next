[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [switch]$ExportConfirmed,
    [switch]$VisualReviewConfirmed,
    [ValidateRange(120, 1800)][int]$TimeoutSeconds = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$exportDriver = Join-Path $PSScriptRoot 'run-p0-dfl-export-fixed-model.py'
$validatorScript = Join-Path $PSScriptRoot 'validate-p0-dfm-export.py'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$modelClass = 'SAEHD'
$modelBaseName = 'p0gate'
$modelPrefix = $modelBaseName + '_' + $modelClass
$expectedIteration = 4
$expectedDfmName = $modelPrefix + '_model.dfm'

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

function Confirm-CloneMatchesInventory {
    param(
        [Parameter(Mandatory = $true)]$Records,
        [Parameter(Mandatory = $true)][string]$CloneDirectory
    )
    foreach ($record in @($Records)) {
        $clonePath = Join-Path $CloneDirectory ([string]$record.name)
        if (-not (Test-Path -LiteralPath $clonePath -PathType Leaf)) { return $false }
        $item = Get-Item -LiteralPath $clonePath -Force -ErrorAction Stop
        if ([int64]$item.Length -ne [int64]$record.size_bytes) { return $false }
        $hash = (Get-FileHash -LiteralPath $clonePath -Algorithm SHA256 -ErrorAction Stop).Hash
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

if (-not $ExportConfirmed) {
    throw 'Step 17 requires explicit confirmation to export the accepted P0 checkpoint.'
}
if (-not $VisualReviewConfirmed) {
    throw 'Step 17 requires confirmation that the three merged images and masks passed visual review.'
}
foreach ($requiredFile in @($exportDriver, $validatorScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Required step-17 file was not found: $requiredFile" }
}

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$runtimeRoot = Normalize-FullPath -Path (Get-ProfileValue 'RuntimeRoot')
$pythonExe = Normalize-FullPath -Path (Get-ProfileValue 'PythonExe')
$deepFaceLabRoot = Normalize-FullPath -Path (Get-ProfileValue 'DeepFaceLabRoot')
$defaultWorkspace = Normalize-FullPath -Path (Get-ProfileValue 'WorkspacePath')
$workspaceResolved = Normalize-FullPath -Path (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$repoRootNormalized = Normalize-FullPath -Path $repoRoot

foreach ($requiredPath in @($runtimeRoot, $pythonExe, $deepFaceLabRoot, $defaultWorkspace, $workspaceResolved)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required path does not exist: $requiredPath" }
}
if (Test-PathInside -Candidate $workspaceResolved -Parent $repoRootNormalized) { throw 'The isolated P0 workspace must remain outside the Git repository.' }
if (Test-PathInside -Candidate $workspaceResolved -Parent $runtimeRoot) { throw 'The isolated P0 workspace must remain outside the historical runtime.' }

$resumeMarkerPath = Join-Path $workspaceResolved 'p0-resume-training-manifest.json'
$mergeMarkerPath = Join-Path $workspaceResolved 'p0-merge-manifest.json'
foreach ($markerPath in @($resumeMarkerPath, $mergeMarkerPath)) {
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw "Required passed workspace marker is missing: $markerPath" }
}
$resumeMarker = Get-Content -LiteralPath $resumeMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
$mergeMarker = Get-Content -LiteralPath $mergeMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string](Get-PropertyValue -Object $resumeMarker -Name 'status' -Default '') -ne 'passed') { throw 'The step-15 marker is not passed.' }
if ([int](Get-PropertyValue -Object $resumeMarker -Name 'after_iteration' -Default -1) -ne $expectedIteration) { throw 'The step-15 marker iteration is not 4.' }
if ([string](Get-PropertyValue -Object $mergeMarker -Name 'status' -Default '') -ne 'passed') { throw 'The step-16 marker is not passed.' }
if ([int](Get-PropertyValue -Object $mergeMarker -Name 'model_iteration' -Default -1) -ne $expectedIteration) { throw 'The step-16 marker model iteration is not 4.' }
if ([int](Get-PropertyValue -Object $mergeMarker -Name 'merged_count' -Default -1) -ne 3) { throw 'The step-16 marker merged count is not 3.' }
if ([int](Get-PropertyValue -Object $mergeMarker -Name 'mask_count' -Default -1) -ne 3) { throw 'The step-16 marker mask count is not 3.' }

$modelDirectory = Join-Path $workspaceResolved 'model'
$destinationInput = Join-Path $workspaceResolved 'data_dst'
$destinationAligned = Join-Path $workspaceResolved 'data_dst\aligned'
$mergedDirectory = Join-Path $workspaceResolved 'merged'
$maskDirectory = Join-Path $workspaceResolved 'merged_mask'
$dfmDirectory = Join-Path $workspaceResolved 'dfm'
$dfmManifestPath = Join-Path $workspaceResolved 'p0-dfm-export-manifest.json'
foreach ($directory in @($modelDirectory, $destinationInput, $destinationAligned, $mergedDirectory, $maskDirectory)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Required workspace directory is missing: $directory" }
}
if (Test-Path -LiteralPath $dfmManifestPath) { throw 'A P0 DFM export manifest already exists. Nothing was executed.' }
if (Test-Path -LiteralPath $dfmDirectory) {
    if (-not (Test-Path -LiteralPath $dfmDirectory -PathType Container)) { throw 'The DFM output path exists but is not a directory.' }
    if (@(Get-ChildItem -LiteralPath $dfmDirectory -Force -ErrorAction Stop).Count -ne 0) { throw 'The final DFM directory must be empty before step 17.' }
}
if (@(Get-ChildItem -LiteralPath $modelDirectory -File -Force -ErrorAction Stop).Count -ne 8) { throw 'Step 17 expects the accepted eight-file checkpoint.' }
if (@(Get-ChildItem -LiteralPath $modelDirectory -Filter '*.dfm' -File -Force -ErrorAction Stop).Count -ne 0) { throw 'The formal model directory must not contain a DFM file before step 17.' }
if (@(Get-ChildItem -LiteralPath $mergedDirectory -File -Force -ErrorAction Stop).Count -ne 3) { throw 'Step 17 expects exactly three committed merged images.' }
if (@(Get-ChildItem -LiteralPath $maskDirectory -File -Force -ErrorAction Stop).Count -ne 3) { throw 'Step 17 expects exactly three committed mask images.' }

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) { throw 'The Git working tree is not clean.' }
$defaultWorkspaceBefore = Get-TreeSnapshot -Path $defaultWorkspace
$modelInventory = Get-FileInventory -Directory $modelDirectory
$destinationInventory = Get-FileInventory -Directory $destinationInput
$alignedInventory = Get-FileInventory -Directory $destinationAligned
$mergedInventoryBefore = Get-FileInventory -Directory $mergedDirectory
$maskInventoryBefore = Get-FileInventory -Directory $maskDirectory

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
$isolatedPath = (@($pathEntriesList) -join ';')

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$artifactRoot = Join-Path $repoRoot ("artifacts\p0\{0}\{1}" -f $machineId, $environmentId)
$outputDirectory = Join-Path $artifactRoot 'dfm-export'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("p0-controlled-dfm-export-{0}.json" -f $fileTimestamp)
$exportStdoutPath = Join-Path $outputDirectory ($fileTimestamp + '.export.stdout.txt')
$exportStderrPath = Join-Path $outputDirectory ($fileTimestamp + '.export.stderr.txt')
$validationStdoutPath = Join-Path $outputDirectory ($fileTimestamp + '.validate.stdout.txt')
$validationStderrPath = Join-Path $outputDirectory ($fileTimestamp + '.validate.stderr.txt')
$stagingRoot = Join-Path $workspaceResolved ('.dfm-export-p0-staging-' + [Guid]::NewGuid().ToString('N'))
$stagingModel = Join-Path $stagingRoot 'model'
$stagingDfmPath = Join-Path $stagingModel $expectedDfmName
$finalDfmPath = Join-Path $dfmDirectory $expectedDfmName

$exportProcess = $null
$validationProcess = $null
$exportParse = [ordered]@{ value = $null; error = 'Export was not run.' }
$validationParse = [ordered]@{ value = $null; error = 'DFM validation was not run.' }
$cloneVerifiedBefore = $false
$cloneCheckpointUnchanged = $false
$modelUnchanged = $false
$destinationUnchanged = $false
$alignedUnchanged = $false
$mergedUnchanged = $false
$maskUnchanged = $false
$defaultWorkspaceUnchanged = $false
$repoUnchanged = $false
$commitSucceeded = $false
$status = 'blocked_not_started'
$fatalError = $null

Write-Host ''
Write-Host '[1/4] Verifying merge acceptance and cloning the iteration-4 checkpoint...' -ForegroundColor Cyan
Write-Host ("Profile: {0}" -f $profileResolved)
Write-Host ("Isolated workspace: {0}" -f $workspaceResolved)
Write-Host ("Model: {0}; iteration: {1}; checkpoint files: {2}" -f $modelPrefix, $expectedIteration, @($modelInventory).Count)
Write-Host ("Merged images visually accepted: {0}; timeout: {1}s" -f $VisualReviewConfirmed.IsPresent, $TimeoutSeconds)
Write-Host ("Official export device mode: CPU-only; bundled CUDA/cuDNN DLL files available: {0}" -f $dllFiles.Count)

try {
    New-Item -ItemType Directory -Path $stagingModel -Force | Out-Null
    foreach ($record in @($modelInventory)) {
        Copy-Item -LiteralPath ([string]$record.path) -Destination (Join-Path $stagingModel ([string]$record.name)) -Force -ErrorAction Stop
    }
    $cloneVerifiedBefore = Confirm-CloneMatchesInventory -Records $modelInventory -CloneDirectory $stagingModel
    if (-not $cloneVerifiedBefore) { throw 'The temporary checkpoint clone did not match all formal SHA-256 records.' }

    $exportArguments = @(
        $exportDriver,
        '--dfl-root', $deepFaceLabRoot,
        '--model-dir', $stagingModel,
        '--model-class', $modelClass,
        '--model-name', $modelBaseName,
        '--expected-iteration', [string]$expectedIteration
    )

    Write-Host ''
    Write-Host '[2/4] Exporting one DFM from the temporary checkpoint clone...' -ForegroundColor Cyan
    $exportProcess = Invoke-IsolatedPython -Label 'dfm-export' -Arguments $exportArguments -ProcessTimeoutSeconds $TimeoutSeconds
    [System.IO.File]::WriteAllText($exportStdoutPath, [string]$exportProcess.stdout, $utf8Bom)
    [System.IO.File]::WriteAllText($exportStderrPath, [string]$exportProcess.stderr, $utf8Bom)
    $exportParse = Convert-SentinelJson -Text ([string]$exportProcess.stdout) -BeginMarker '__DFLNEXT_DFM_EXPORT_JSON_BEGIN__' -EndMarker '__DFLNEXT_DFM_EXPORT_JSON_END__'

    $exportPassed = $false
    if (-not $exportProcess.timed_out -and $null -ne $exportProcess.exit_code -and [int]$exportProcess.exit_code -eq 0 -and $null -eq $exportParse.error -and $null -ne $exportParse.value) {
        $exportPassed = [string](Get-PropertyValue -Object $exportParse.value -Name 'status' -Default '') -eq 'passed'
    }

    if ($exportPassed) {
        Write-Host ''
        Write-Host '[3/4] Validating ONNX structure, tensor names, opset, and checkpoint immutability...' -ForegroundColor Cyan
        $validationArguments = @(
            $validatorScript,
            $stagingModel,
            $modelPrefix,
            [string]$expectedIteration,
            $expectedDfmName
        )
        $validationProcess = Invoke-IsolatedPython -Label 'dfm-validation' -Arguments $validationArguments -ProcessTimeoutSeconds 180
        [System.IO.File]::WriteAllText($validationStdoutPath, [string]$validationProcess.stdout, $utf8Bom)
        [System.IO.File]::WriteAllText($validationStderrPath, [string]$validationProcess.stderr, $utf8Bom)
        $validationParse = Convert-SentinelJson -Text ([string]$validationProcess.stdout) -BeginMarker '__DFLNEXT_DFM_VALIDATION_JSON_BEGIN__' -EndMarker '__DFLNEXT_DFM_VALIDATION_JSON_END__'
    }
    else {
        [System.IO.File]::WriteAllText($validationStdoutPath, '', $utf8Bom)
        [System.IO.File]::WriteAllText($validationStderrPath, '', $utf8Bom)
    }

    $cloneCheckpointUnchanged = Confirm-CloneMatchesInventory -Records $modelInventory -CloneDirectory $stagingModel
    $modelUnchanged = Confirm-InventoryUnchanged -Records $modelInventory
    $destinationUnchanged = Confirm-InventoryUnchanged -Records $destinationInventory
    $alignedUnchanged = Confirm-InventoryUnchanged -Records $alignedInventory
    $mergedUnchanged = Confirm-InventoryUnchanged -Records $mergedInventoryBefore
    $maskUnchanged = Confirm-InventoryUnchanged -Records $maskInventoryBefore
    $defaultWorkspaceAfter = Get-TreeSnapshot -Path $defaultWorkspace
    $defaultWorkspaceUnchanged = $defaultWorkspaceBefore.metadata_sha256 -eq $defaultWorkspaceAfter.metadata_sha256
    $repoStatusAfter = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
    $repoUnchanged = $repoStatusBefore -eq $repoStatusAfter

    $validatorPassed = $false
    if ($null -ne $validationProcess -and -not $validationProcess.timed_out -and $null -ne $validationProcess.exit_code -and [int]$validationProcess.exit_code -eq 0 -and $null -eq $validationParse.error -and $null -ne $validationParse.value) {
        $validatorPassed = [string](Get-PropertyValue -Object $validationParse.value -Name 'status' -Default '') -eq 'passed'
    }

    $stagingFiles = @(Get-ChildItem -LiteralPath $stagingModel -File -Force -ErrorAction Stop)
    $stagingDfmCount = @($stagingFiles | Where-Object { $_.Extension -ieq '.dfm' }).Count
    $stagingNonDfmCount = @($stagingFiles | Where-Object { $_.Extension -ine '.dfm' }).Count

    if ($null -eq $exportProcess) { $status = 'blocked_export_not_started' }
    elseif ($exportProcess.timed_out) { $status = 'blocked_export_timeout' }
    elseif ($null -eq $exportProcess.exit_code -or [int]$exportProcess.exit_code -ne 0) { $status = 'blocked_export_process' }
    elseif ($null -ne $exportParse.error -or $null -eq $exportParse.value -or [string](Get-PropertyValue -Object $exportParse.value -Name 'status' -Default '') -ne 'passed') { $status = 'blocked_export_result' }
    elseif (-not $validatorPassed) { $status = 'blocked_invalid_dfm' }
    elseif ($stagingDfmCount -ne 1 -or $stagingNonDfmCount -ne @($modelInventory).Count) { $status = 'blocked_unexpected_staging_files' }
    elseif (-not $cloneCheckpointUnchanged) { $status = 'blocked_staging_checkpoint_changed' }
    elseif (-not $modelUnchanged) { $status = 'blocked_formal_checkpoint_changed' }
    elseif (-not $destinationUnchanged) { $status = 'blocked_destination_changed' }
    elseif (-not $alignedUnchanged) { $status = 'blocked_aligned_changed' }
    elseif (-not $mergedUnchanged) { $status = 'blocked_merged_changed' }
    elseif (-not $maskUnchanged) { $status = 'blocked_mask_changed' }
    elseif (-not $defaultWorkspaceUnchanged) { $status = 'blocked_historical_workspace_changed' }
    elseif (-not $repoUnchanged) { $status = 'blocked_repository_changed' }
    elseif (-not (Test-Path -LiteralPath $stagingDfmPath -PathType Leaf)) { $status = 'blocked_expected_dfm_missing' }
    else {
        if (-not (Test-Path -LiteralPath $dfmDirectory)) {
            New-Item -ItemType Directory -Path $dfmDirectory -Force | Out-Null
        }
        Move-Item -LiteralPath $stagingDfmPath -Destination $finalDfmPath -ErrorAction Stop
        $expectedHash = [string](Get-PropertyValue -Object $validationParse.value -Name 'dfm_sha256' -Default '')
        $actualHash = (Get-FileHash -LiteralPath $finalDfmPath -Algorithm SHA256 -ErrorAction Stop).Hash
        if ([string]::IsNullOrWhiteSpace($expectedHash) -or $actualHash -ne $expectedHash) {
            Remove-Item -LiteralPath $finalDfmPath -Force -ErrorAction SilentlyContinue
            throw 'The committed DFM hash did not match the validated staging DFM.'
        }
        $commitSucceeded = $true
        $status = 'passed'
    }
}
catch {
    $fatalError = $_.Exception.ToString()
    if ($status -eq 'blocked_not_started') { $status = 'blocked_exception' }
    if (-not $commitSucceeded -and (Test-Path -LiteralPath $finalDfmPath -PathType Leaf)) {
        Remove-Item -LiteralPath $finalDfmPath -Force -ErrorAction SilentlyContinue
    }
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not $commitSucceeded -and (Test-Path -LiteralPath $dfmDirectory -PathType Container)) {
        if (@(Get-ChildItem -LiteralPath $dfmDirectory -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $dfmDirectory -Force -ErrorAction SilentlyContinue
        }
    }
}

$finalDfmInventory = @()
if ($commitSucceeded -and (Test-Path -LiteralPath $dfmDirectory -PathType Container)) {
    $finalDfmInventory = Get-FileInventory -Directory $dfmDirectory
}
$actualIteration = $null
$dfmSizeBytes = [int64]0
$dfmSha256 = $null
$onnxCheckerPassed = $false
$opsetVersions = @()
$inputNames = @()
$outputNames = @()
if ($null -ne $validationParse.value) {
    $actualIteration = Get-PropertyValue -Object $validationParse.value -Name 'actual_iteration' -Default $null
    $dfmSizeBytes = [int64](Get-PropertyValue -Object $validationParse.value -Name 'dfm_size_bytes' -Default 0)
    $dfmSha256 = Get-PropertyValue -Object $validationParse.value -Name 'dfm_sha256' -Default $null
    $onnxCheckerPassed = [bool](Get-PropertyValue -Object $validationParse.value -Name 'onnx_checker_passed' -Default $false)
    $opsetVersions = @(Get-PropertyValue -Object $validationParse.value -Name 'opset_versions' -Default @())
    $inputNames = @(Get-PropertyValue -Object $validationParse.value -Name 'input_names' -Default @())
    $outputNames = @(Get-PropertyValue -Object $validationParse.value -Name 'output_names' -Default @())
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'p0_controlled_dfm_export_gate'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    workspace_root = $workspaceResolved
    parameters = [ordered]@{
        model_class = $modelClass
        model_prefix = $modelPrefix
        expected_iteration = $expectedIteration
        export_device = 'cpu_only_official_historical_path'
        expected_dfm_name = $expectedDfmName
        timeout_seconds = $TimeoutSeconds
        visual_review_confirmed = $VisualReviewConfirmed.IsPresent
    }
    checkpoint_clone = [ordered]@{
        staging_path = $stagingModel
        formal_file_count = @($modelInventory).Count
        verified_before_export = $cloneVerifiedBefore
        checkpoint_files_unchanged_after_export = $cloneCheckpointUnchanged
        staging_removed = -not (Test-Path -LiteralPath $stagingRoot)
    }
    export_process = if ($null -eq $exportProcess) { $null } else { [ordered]@{
        timed_out = $exportProcess.timed_out
        exit_code = $exportProcess.exit_code
        stdout_file = $exportStdoutPath
        stderr_file = $exportStderrPath
        parse_error = $exportParse.error
        result = $exportParse.value
        stdout_tail = Limit-Text -Text ([string]$exportProcess.stdout)
        stderr_tail = Limit-Text -Text ([string]$exportProcess.stderr)
    }}
    validation = [ordered]@{
        stdout_file = $validationStdoutPath
        stderr_file = $validationStderrPath
        parse_error = $validationParse.error
        result = $validationParse.value
    }
    output = [ordered]@{
        committed = $commitSucceeded
        directory = $dfmDirectory
        path = if ($commitSucceeded) { $finalDfmPath } else { $null }
        files = @($finalDfmInventory)
        size_bytes = $dfmSizeBytes
        sha256 = $dfmSha256
        onnx_checker_passed = $onnxCheckerPassed
        opset_versions = @($opsetVersions)
        input_names = @($inputNames)
        output_names = @($outputNames)
    }
    environment_checks = [ordered]@{
        formal_checkpoint_unchanged = $modelUnchanged
        destination_inputs_unchanged = $destinationUnchanged
        destination_aligned_unchanged = $alignedUnchanged
        merged_outputs_unchanged = $mergedUnchanged
        merge_masks_unchanged = $maskUnchanged
        historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
        repository_unchanged = $repoUnchanged
    }
    safety = [ordered]@{
        authorized_synthetic_inputs_only = $true
        manual_merge_visual_review_confirmed = $VisualReviewConfirmed.IsPresent
        temporary_checkpoint_clone_used = $true
        formal_model_directory_received_export_output = $false
        training_started = $false
        merge_started = $false
        visomaster_load_started = $false
        historical_default_workspace_modified = $false
    }
    fatal_error = $fatalError
    next_action = if ($status -eq 'passed') { 'Load the committed local DFM in VisoMaster Fusion and record the compatibility result.' } else { 'Review export and validation logs. Do not manually export or load a partial DFM.' }
}
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 24), $utf8Bom)

if ($status -eq 'passed') {
    $workspaceReport = [ordered]@{
        schema_version = 1
        generated_at_utc = $timestamp.ToString('o')
        status = $status
        profile_path = $profileResolved
        workspace_root = $workspaceResolved
        artifact_report = $reportPath
        model_prefix = $modelPrefix
        model_iteration = $actualIteration
        visual_review_confirmed = $VisualReviewConfirmed.IsPresent
        dfm_path = $finalDfmPath
        dfm_name = $expectedDfmName
        dfm_size_bytes = $dfmSizeBytes
        dfm_sha256 = $dfmSha256
        onnx_checker_passed = $onnxCheckerPassed
        opset_versions = @($opsetVersions)
        input_names = @($inputNames)
        output_names = @($outputNames)
    }
    [System.IO.File]::WriteAllText($dfmManifestPath, ($workspaceReport | ConvertTo-Json -Depth 12), $utf8Bom)
}

Write-Host ''
Write-Host '[4/4] Controlled P0 DFM export result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Model: {0}; iteration: {1}" -f $modelPrefix, $actualIteration)
Write-Host ("DFM committed: {0}; files: {1}; size bytes: {2}" -f $commitSucceeded, @($finalDfmInventory).Count, $dfmSizeBytes)
Write-Host ("ONNX checker passed: {0}; opsets: {1}" -f $onnxCheckerPassed, (@($opsetVersions) -join ','))
Write-Host ("Inputs: {0}" -f (@($inputNames) -join ','))
Write-Host ("Outputs: {0}" -f (@($outputNames) -join ','))
Write-Host ("Checkpoint clone verified: {0}; formal checkpoint unchanged: {1}" -f $cloneVerifiedBefore, $modelUnchanged)
Write-Host ("Merged outputs unchanged: {0}; masks unchanged: {1}" -f $mergedUnchanged, $maskUnchanged)
Write-Host ("Historical default workspace unchanged: {0}" -f $defaultWorkspaceUnchanged)
Write-Host ("Repository unchanged: {0}" -f $repoUnchanged)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ''
Write-Host 'Safety boundary' -ForegroundColor Cyan
if ($status -eq 'passed') {
    Write-Host 'One validated DFM was exported from a temporary checkpoint clone and committed locally. VisoMaster Fusion was not opened automatically.' -ForegroundColor Yellow
}
else {
    Write-Host 'Temporary DFM output was blocked and removed. The accepted iteration-4 checkpoint and merged outputs were preserved.' -ForegroundColor Yellow
}

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    model_prefix = $modelPrefix
    model_iteration = $actualIteration
    visual_review_confirmed = $VisualReviewConfirmed.IsPresent
    dfm_committed = $commitSucceeded
    dfm_path = if ($commitSucceeded) { $finalDfmPath } else { $null }
    dfm_file_count = @($finalDfmInventory).Count
    dfm_size_bytes = $dfmSizeBytes
    dfm_sha256 = $dfmSha256
    onnx_checker_passed = $onnxCheckerPassed
    checkpoint_clone_verified = $cloneVerifiedBefore
    formal_checkpoint_unchanged = $modelUnchanged
    merged_outputs_unchanged = $mergedUnchanged
    merge_masks_unchanged = $maskUnchanged
    historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
    repository_unchanged = $repoUnchanged
}

if ($status -ne 'passed') { exit 1 }
exit 0
