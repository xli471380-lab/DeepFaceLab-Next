[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [switch]$VisualReviewConfirmed,
    [ValidateRange(300, 1800)][int]$TimeoutSeconds = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$validatorScript = Join-Path $PSScriptRoot 'validate-p0-training-checkpoint.py'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$modelClass = 'SAEHD'
$modelBaseName = 'p0gate'
$modelPrefix = $modelBaseName + '_' + $modelClass
$targetIteration = 2

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
        [Parameter(Mandatory = $true)][int]$ProcessTimeoutSeconds,
        [string[]]$InputLines = @()
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
    $stdinError = $null

    try {
        $started = $process.Start()
        if (-not $started) { throw ("Process did not start: {0}" -f $Label) }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        try {
            foreach ($line in @($InputLines)) { $process.StandardInput.WriteLine([string]$line) }
            $process.StandardInput.Close()
        }
        catch {
            $stdinError = $_.Exception.ToString()
        }

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
        stdin_error = $stdinError
        stdout = $stdout
        stderr = $stderr
    }
}

function Convert-CheckpointValidation {
    param([AllowEmptyString()][string]$Text)
    $pattern = '(?s)__DFLNEXT_TRAINING_CHECKPOINT_JSON_BEGIN__\s*(.*?)\s*__DFLNEXT_TRAINING_CHECKPOINT_JSON_END__'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return [ordered]@{ value = $null; error = 'Checkpoint validation sentinel JSON markers were not found.' }
    }
    try {
        return [ordered]@{ value = ($match.Groups[1].Value | ConvertFrom-Json); error = $null }
    }
    catch {
        return [ordered]@{ value = $null; error = $_.Exception.Message }
    }
}

if (-not $VisualReviewConfirmed) {
    throw 'The six aligned synthetic faces must be visually reviewed before step 14.'
}
if (-not (Test-Path -LiteralPath $validatorScript -PathType Leaf)) {
    throw "Training checkpoint validator was not found: $validatorScript"
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

$workspaceMarkerPath = Join-Path $workspaceResolved 'p0-workspace-manifest.json'
$extractionMarkerPath = Join-Path $workspaceResolved 'p0-face-extraction-manifest.json'
foreach ($markerPath in @($workspaceMarkerPath, $extractionMarkerPath)) {
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw "Required P0 workspace marker was not found: $markerPath" }
}
$workspaceMarker = Get-Content -LiteralPath $workspaceMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
$extractionMarker = Get-Content -LiteralPath $extractionMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string](Get-PropertyValue -Object $extractionMarker -Name 'status' -Default '') -ne 'passed') { throw 'The step-13 extraction marker is not passed.' }
if ([int](Get-PropertyValue -Object $extractionMarker -Name 'source_aligned_count' -Default 0) -ne 3) { throw 'The source aligned count is not 3.' }
if ([int](Get-PropertyValue -Object $extractionMarker -Name 'destination_aligned_count' -Default 0) -ne 3) { throw 'The destination aligned count is not 3.' }

$sourceAligned = Join-Path $workspaceResolved 'data_src\aligned'
$destinationAligned = Join-Path $workspaceResolved 'data_dst\aligned'
$modelDirectory = Join-Path $workspaceResolved 'model'
foreach ($directory in @($sourceAligned, $destinationAligned, $modelDirectory)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Required workspace directory is missing: $directory" }
}
$sourceFiles = @(Get-ChildItem -LiteralPath $sourceAligned -Filter '*.jpg' -File -Force -ErrorAction Stop | Sort-Object Name)
$destinationFiles = @(Get-ChildItem -LiteralPath $destinationAligned -Filter '*.jpg' -File -Force -ErrorAction Stop | Sort-Object Name)
if ($sourceFiles.Count -ne 3 -or $destinationFiles.Count -ne 3) { throw 'Step 14 requires exactly 3 aligned JPG files per role.' }
if (@(Get-ChildItem -LiteralPath $modelDirectory -Force -ErrorAction Stop).Count -ne 0) {
    throw "The final model directory must be empty before step 14; nothing will be deleted: $modelDirectory"
}

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) { throw 'The Git working tree is not clean.' }
$defaultWorkspaceBefore = Get-TreeSnapshot -Path $defaultWorkspace
$sourceInventory = Get-FileInventory -Directory $sourceAligned
$destinationInventory = Get-FileInventory -Directory $destinationAligned

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
$outputDirectory = Join-Path $artifactRoot 'initial-training-save'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("p0-initial-training-save-{0}.json" -f $fileTimestamp)
$trainingStdoutPath = Join-Path $outputDirectory ($fileTimestamp + '.train.stdout.txt')
$trainingStderrPath = Join-Path $outputDirectory ($fileTimestamp + '.train.stderr.txt')
$validationStdoutPath = Join-Path $outputDirectory ($fileTimestamp + '.validate.stdout.txt')
$validationStderrPath = Join-Path $outputDirectory ($fileTimestamp + '.validate.stderr.txt')
$stagingModelDirectory = Join-Path $workspaceResolved ('.model-p0-first-run-staging-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $stagingModelDirectory) { throw 'Unexpected staging model directory collision.' }
New-Item -ItemType Directory -Path $stagingModelDirectory -Force | Out-Null

$promptAnswers = @(
    '0',
    'n',
    [string]$targetIteration,
    'n',
    'n',
    '2',
    '96',
    'wf',
    'df',
    '64',
    '32',
    '32',
    '16',
    'y',
    'n',
    'n',
    'n',
    'y',
    'n',
    'n',
    'y',
    '0',
    '0',
    '0',
    '0',
    '0',
    'none',
    'n',
    'n'
)
$closeProgram = "s2c.put({'op':'close'}) if model.get_iter() >= 2 else None"
$trainingArguments = @(
    $mainPy,
    'train',
    '--training-data-src-dir', $sourceAligned,
    '--training-data-dst-dir', $destinationAligned,
    '--model-dir', $stagingModelDirectory,
    '--model', $modelClass,
    '--no-preview',
    '--force-model-name', $modelBaseName,
    '--force-gpu-idxs', '0',
    '--execute-program', '-1', $closeProgram
)

Write-Host ''
Write-Host '[1/4] Preconditions, aligned faces, and immutable hashes passed.' -ForegroundColor Cyan
Write-Host ("Profile: {0}" -f $profileResolved)
Write-Host ("Isolated workspace: {0}" -f $workspaceResolved)
Write-Host ("Model: {0}; target iteration: {1}; timeout: {2}s" -f $modelClass, $targetIteration, $TimeoutSeconds)
Write-Host ("Bundled CUDA/cuDNN DLL files selected: {0}" -f $dllFiles.Count)
Write-Host ''
Write-Host '[2/4] Running bounded first SAEHD training, graceful save, and exit...' -ForegroundColor Cyan

$trainingProcess = $null
$validationProcess = $null
$validationParse = [ordered]@{ value = $null; error = 'Checkpoint validator was not run.' }
$inputsUnchanged = $false
$defaultWorkspaceUnchanged = $false
$repoUnchanged = $false
$commitSucceeded = $false
$status = 'blocked_not_started'
$fatalError = $null

try {
    $trainingProcess = Invoke-IsolatedPython -Label 'initial-training' -Arguments $trainingArguments -ProcessTimeoutSeconds $TimeoutSeconds -InputLines $promptAnswers
    [System.IO.File]::WriteAllText($trainingStdoutPath, [string]$trainingProcess.stdout, $utf8Bom)
    [System.IO.File]::WriteAllText($trainingStderrPath, [string]$trainingProcess.stderr, $utf8Bom)

    $trainingCompleted = (-not $trainingProcess.timed_out) -and ($null -ne $trainingProcess.exit_code) -and ([int]$trainingProcess.exit_code -eq 0) -and ($null -eq $trainingProcess.stdin_error)
    if ($trainingCompleted) {
        Write-Host '  validating saved SAEHD checkpoint and fixed options...' -ForegroundColor Cyan
        $validationArguments = @($validatorScript, $stagingModelDirectory, $modelPrefix, [string]$targetIteration)
        $validationProcess = Invoke-IsolatedPython -Label 'checkpoint-validation' -Arguments $validationArguments -ProcessTimeoutSeconds 60
        [System.IO.File]::WriteAllText($validationStdoutPath, [string]$validationProcess.stdout, $utf8Bom)
        [System.IO.File]::WriteAllText($validationStderrPath, [string]$validationProcess.stderr, $utf8Bom)
        $validationParse = Convert-CheckpointValidation -Text ([string]$validationProcess.stdout)
    }
    else {
        [System.IO.File]::WriteAllText($validationStdoutPath, '', $utf8Bom)
        [System.IO.File]::WriteAllText($validationStderrPath, '', $utf8Bom)
    }

    $inputsUnchanged = (Confirm-InventoryUnchanged -Records $sourceInventory) -and (Confirm-InventoryUnchanged -Records $destinationInventory)
    $defaultWorkspaceAfter = Get-TreeSnapshot -Path $defaultWorkspace
    $defaultWorkspaceUnchanged = $defaultWorkspaceBefore.metadata_sha256 -eq $defaultWorkspaceAfter.metadata_sha256
    $repoStatusAfter = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
    $repoUnchanged = $repoStatusBefore -eq $repoStatusAfter

    $validatorPassed = $false
    if ($null -ne $validationProcess -and -not $validationProcess.timed_out -and $null -ne $validationProcess.exit_code -and [int]$validationProcess.exit_code -eq 0 -and $null -eq $validationParse.error -and $null -ne $validationParse.value) {
        $validatorPassed = [string](Get-PropertyValue -Object $validationParse.value -Name 'status' -Default '') -eq 'passed'
    }

    if ($null -eq $trainingProcess) { $status = 'blocked_training_not_started' }
    elseif ($trainingProcess.timed_out) { $status = 'blocked_training_timeout' }
    elseif ($null -ne $trainingProcess.stdin_error) { $status = 'blocked_training_stdin' }
    elseif ($null -eq $trainingProcess.exit_code -or [int]$trainingProcess.exit_code -ne 0) { $status = 'blocked_training_process' }
    elseif (-not $validatorPassed) { $status = 'blocked_invalid_checkpoint' }
    elseif (-not $inputsUnchanged) { $status = 'blocked_aligned_input_changed' }
    elseif (-not $defaultWorkspaceUnchanged) { $status = 'blocked_historical_workspace_changed' }
    elseif (-not $repoUnchanged) { $status = 'blocked_repository_changed' }
    else {
        Remove-Item -LiteralPath $modelDirectory -Force -ErrorAction Stop
        Move-Item -LiteralPath $stagingModelDirectory -Destination $modelDirectory -ErrorAction Stop
        $commitSucceeded = $true
        $status = 'passed'
    }
}
catch {
    $fatalError = $_.Exception.ToString()
    if ($status -eq 'blocked_not_started') { $status = 'blocked_exception' }
}
finally {
    if (-not $commitSucceeded -and (Test-Path -LiteralPath $stagingModelDirectory)) {
        Remove-Item -LiteralPath $stagingModelDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $modelDirectory)) {
        New-Item -ItemType Directory -Path $modelDirectory -Force | Out-Null
    }
}

$modelFiles = @()
if ($commitSucceeded) { $modelFiles = Get-FileInventory -Directory $modelDirectory }
$iteration = $null
$lossHistoryCount = $null
if ($null -ne $validationParse.value) {
    $iteration = Get-PropertyValue -Object $validationParse.value -Name 'iteration' -Default $null
    $lossHistoryCount = Get-PropertyValue -Object $validationParse.value -Name 'loss_history_count' -Default $null
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'p0_initial_training_save_gate'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    workspace_root = $workspaceResolved
    visual_review_confirmed = $true
    parameters = [ordered]@{
        model_class = $modelClass
        model_base_name = $modelBaseName
        model_prefix = $modelPrefix
        target_iteration = $targetIteration
        resolution = 96
        face_type = 'wf'
        architecture = 'df'
        batch_size = 2
        gpu_index = 0
        no_preview = $true
        timeout_seconds = $TimeoutSeconds
        automatic_close_condition = 'model.get_iter() >= 2'
    }
    training_process = if ($null -eq $trainingProcess) { $null } else { [ordered]@{
        timed_out = $trainingProcess.timed_out
        exit_code = $trainingProcess.exit_code
        stdin_error = $trainingProcess.stdin_error
        stdout_file = $trainingStdoutPath
        stderr_file = $trainingStderrPath
        stdout_tail = Limit-Text -Text ([string]$trainingProcess.stdout)
        stderr_tail = Limit-Text -Text ([string]$trainingProcess.stderr)
    }}
    validation = [ordered]@{
        stdout_file = $validationStdoutPath
        stderr_file = $validationStderrPath
        parse_error = $validationParse.error
        result = $validationParse.value
    }
    checkpoint = [ordered]@{
        committed = $commitSucceeded
        final_model_directory = $modelDirectory
        iteration = $iteration
        loss_history_count = $lossHistoryCount
        files = @($modelFiles)
    }
    environment_checks = [ordered]@{
        aligned_inputs_unchanged = $inputsUnchanged
        historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
        repository_unchanged = $repoUnchanged
    }
    isolation = [ordered]@{
        isolated_path_entries = @($pathEntries)
        bundled_dll_file_count = $dllFiles.Count
        temporary_model_then_commit = $true
        partial_staging_removed_on_block = $true
    }
    safety = [ordered]@{
        authorized_synthetic_inputs_only = $true
        model_created = $commitSucceeded
        training_started = $null -ne $trainingProcess
        training_bounded_to_target_iteration = $true
        graceful_save_and_exit_requested = $true
        resume_started = $false
        merge_started = $false
        dfm_export_started = $false
        historical_default_workspace_modified = $false
    }
    fatal_error = $fatalError
    next_action = if ($status -eq 'passed') { 'Inspect the two-iteration checkpoint, then implement a separate resume gate. Do not merge or export yet.' } else { 'Review the training and validation logs. Do not retry manually or start merge/export.' }
}
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 16), $utf8Bom)

if ($status -eq 'passed') {
    $workspaceTrainingManifest = Join-Path $workspaceResolved 'p0-initial-training-manifest.json'
    $workspaceReport = [ordered]@{
        schema_version = 1
        generated_at_utc = $timestamp.ToString('o')
        status = $status
        profile_path = $profileResolved
        workspace_root = $workspaceResolved
        artifact_report = $reportPath
        model_class = $modelClass
        model_prefix = $modelPrefix
        iteration = $iteration
        loss_history_count = $lossHistoryCount
        model_directory = $modelDirectory
        checkpoint_file_count = @($modelFiles).Count
    }
    [System.IO.File]::WriteAllText($workspaceTrainingManifest, ($workspaceReport | ConvertTo-Json -Depth 8), $utf8Bom)
}

Write-Host ''
Write-Host '[3/4] Initial training and save result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Model: {0}; iteration: {1}; loss history: {2}" -f $modelPrefix, $iteration, $lossHistoryCount)
Write-Host ("Checkpoint committed: {0}; files: {1}" -f $commitSucceeded, @($modelFiles).Count)
Write-Host ("Aligned inputs unchanged: {0}" -f $inputsUnchanged)
Write-Host ("Historical default workspace unchanged: {0}" -f $defaultWorkspaceUnchanged)
Write-Host ("Repository unchanged: {0}" -f $repoUnchanged)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ''
Write-Host '[4/4] Safety boundary' -ForegroundColor Cyan
Write-Host 'Only a two-iteration SAEHD checkpoint was created and saved. Resume, merge, and DFM export were not started.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    model_prefix = $modelPrefix
    iteration = $iteration
    loss_history_count = $lossHistoryCount
    checkpoint_committed = $commitSucceeded
    checkpoint_file_count = @($modelFiles).Count
    aligned_inputs_unchanged = $inputsUnchanged
    historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
    repository_unchanged = $repoUnchanged
}

if ($status -ne 'passed') { exit 1 }
exit 0
