[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [switch]$AntivirusScanConfirmed,
    [ValidateRange(30, 600)][int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$workerScript = Join-Path $PSScriptRoot 'legacy-tensorflow-gpu-visibility-probe.py'
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved

function Get-ProfileValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $profile.ContainsKey($Name)) { throw "Missing profile key: $Name" }
    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Empty profile value: $Name" }
    return $value
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
}

function Limit-Text {
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [int]$MaximumCharacters = 16384
    )

    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $MaximumCharacters) { return $Text }
    return $Text.Substring($Text.Length - $MaximumCharacters) + "`n...[tail retained]"
}

function Quote-NativeArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Get-WorkspaceSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $items = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
    $files = @($items | Where-Object { -not $_.PSIsContainer })
    $directories = @($items | Where-Object { $_.PSIsContainer })
    $builder = New-Object System.Text.StringBuilder

    foreach ($item in $items) {
        $relative = $item.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
        $kind = if ($item.PSIsContainer) { 'D' } else { 'F' }
        $length = if ($item.PSIsContainer) { 0 } else { [int64]$item.Length }
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

function Read-StageRecord {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Convert-WorkerResult {
    param([AllowEmptyString()][string]$Text)

    $match = [regex]::Match($Text, '(?s)__DFLNEXT_TF_GPU_JSON_BEGIN__\s*(.*?)\s*__DFLNEXT_TF_GPU_JSON_END__')
    if (-not $match.Success) {
        return [ordered]@{ value = $null; error = 'TensorFlow/GPU sentinel JSON markers were not found.' }
    }

    try {
        return [ordered]@{ value = ($match.Groups[1].Value | ConvertFrom-Json); error = $null }
    }
    catch {
        return [ordered]@{ value = $null; error = $_.Exception.Message }
    }
}

if (-not $AntivirusScanConfirmed) {
    throw 'The active-antivirus zero-risk scan confirmation was not supplied. Run through step 10 BAT and confirm the scan before importing TensorFlow.'
}
if (-not (Test-Path -LiteralPath $workerScript -PathType Leaf)) {
    throw "TensorFlow/GPU worker script was not found: $workerScript"
}

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$runtimeRoot = Get-ProfileValue 'RuntimeRoot'
$pythonExe = Get-ProfileValue 'PythonExe'
$deepFaceLabRoot = Get-ProfileValue 'DeepFaceLabRoot'
$mainPy = Get-ProfileValue 'MainPy'
$workspacePath = Get-ProfileValue 'WorkspacePath'

foreach ($path in @($runtimeRoot, $pythonExe, $deepFaceLabRoot, $mainPy, $workspacePath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required historical runtime path does not exist: $path" }
}

$layoutDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\python-layout-inspection" -f $machineId, $environmentId)
$layoutReport = Get-ChildItem -LiteralPath $layoutDirectory -Filter 'legacy-python-layout-inspection-v4-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $layoutReport) {
    throw 'A passed schema v4 step 9 report is required before the TensorFlow/GPU visibility probe.'
}
$layout = Get-Content -LiteralPath $layoutReport.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string]$layout.status -ne 'passed') {
    throw "The latest step 9 report is not passed: $($layoutReport.FullName)"
}
if ([System.IO.Path]::GetFullPath([string]$layout.profile_path) -ne [System.IO.Path]::GetFullPath($profileResolved)) {
    throw 'The latest step 9 report belongs to a different local profile.'
}

$internalRoot = Join-Path $runtimeRoot '_internal'
$pythonRoot = Split-Path -Parent $pythonExe
$dllPatterns = @(
    'cudart64*.dll',
    'cudnn64*.dll',
    'cublas64*.dll',
    'cublasLt64*.dll',
    'cufft64*.dll',
    'curand64*.dll',
    'cusolver64*.dll',
    'cusparse64*.dll',
    'nvrtc64*.dll',
    'nvrtc-builtins64*.dll',
    'zlibwapi.dll'
)
$dllFiles = New-Object System.Collections.ArrayList
foreach ($pattern in $dllPatterns) {
    foreach ($file in @(Get-ChildItem -LiteralPath $internalRoot -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue)) {
        [void]$dllFiles.Add($file)
    }
}
$dllFiles = @($dllFiles | Sort-Object FullName -Unique)
$dllDirectories = @($dllFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)

$pathEntries = New-Object System.Collections.ArrayList
foreach ($candidate in @(
    $pythonRoot,
    (Join-Path $pythonRoot 'Scripts'),
    $internalRoot
) + $dllDirectories + @(
    (Join-Path $env:SystemRoot 'System32'),
    $env:SystemRoot
)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate) -and -not $pathEntries.Contains($candidate)) {
        [void]$pathEntries.Add($candidate)
    }
}
$isolatedPath = @($pathEntries) -join ';'

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\tensorflow-gpu-probe" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("legacy-tensorflow-gpu-visibility-{0}.json" -f $fileTimestamp)
$stdoutPath = Join-Path $outputDirectory ("legacy-tensorflow-gpu-visibility-{0}.stdout.txt" -f $fileTimestamp)
$stderrPath = Join-Path $outputDirectory ("legacy-tensorflow-gpu-visibility-{0}.stderr.txt" -f $fileTimestamp)
$stagePath = Join-Path $outputDirectory ("legacy-tensorflow-gpu-visibility-{0}.stage.json" -f $fileTimestamp)

$workspaceBefore = Get-WorkspaceSnapshot -Path $workspacePath

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $pythonExe
$startInfo.Arguments = (Quote-NativeArgument -Value $workerScript) + ' ' + (Quote-NativeArgument -Value $stagePath)
$startInfo.WorkingDirectory = $outputDirectory
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.EnvironmentVariables['PATH'] = $isolatedPath
$startInfo.EnvironmentVariables['PYTHONHOME'] = ''
$startInfo.EnvironmentVariables['PYTHONPATH'] = ''
$startInfo.EnvironmentVariables['PYTHONNOUSERSITE'] = '1'
$startInfo.EnvironmentVariables['CUDA_PATH'] = ''
$startInfo.EnvironmentVariables['CUDA_HOME'] = ''
$startInfo.EnvironmentVariables['CUDNN_PATH'] = ''
$startInfo.EnvironmentVariables['CUDA_VISIBLE_DEVICES'] = ''
$startInfo.EnvironmentVariables['TF_FORCE_GPU_ALLOW_GROWTH'] = 'true'
$startInfo.EnvironmentVariables['TF_CPP_MIN_LOG_LEVEL'] = '0'
$startInfo.EnvironmentVariables['TF_ENABLE_ONEDNN_OPTS'] = '0'

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
$timedOut = $false
$lastStage = $null
$lastMessage = $null
$stdout = ''
$stderr = ''
$exitCode = $null

Write-Host ''
Write-Host '[1/4] Preconditions passed.' -ForegroundColor Cyan
Write-Host ("Profile: {0}" -f $profileResolved)
Write-Host ("Step 9 report: {0}" -f $layoutReport.FullName)
Write-Host ("Bundled CUDA/cuDNN DLL files selected: {0}" -f $dllFiles.Count)
Write-Host ("Isolated PATH entries: {0}" -f $pathEntries.Count)
Write-Host ''
Write-Host '[2/4] Starting the isolated TensorFlow/GPU visibility worker...' -ForegroundColor Cyan
Write-Host ("Timeout: {0} seconds" -f $TimeoutSeconds)
Write-Host 'No DeepFaceLab main.py, model, tensor workload, or training command is started.'
Write-Host ''

try {
    if (-not $process.Start()) { throw 'Failed to start the embedded Python TensorFlow/GPU worker.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $startedAt = Get-Date
    $nextProgress = 10

    while (-not $process.HasExited) {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        $stage = Read-StageRecord -Path $stagePath
        if ($null -ne $stage) {
            $stageName = [string]$stage.stage
            $stageMessage = [string]$stage.message
            if ($stageName -ne $lastStage -or $stageMessage -ne $lastMessage) {
                Write-Host ("Stage: {0}" -f $stageName) -ForegroundColor Cyan
                Write-Host ("  {0}" -f $stageMessage)
                $lastStage = $stageName
                $lastMessage = $stageMessage
            }
        }

        $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
        if ($elapsed -ge $nextProgress) {
            $stageText = if ([string]::IsNullOrWhiteSpace($lastStage)) { 'starting' } else { $lastStage }
            Write-Host ("Still running... elapsed {0}s / timeout {1}s / stage {2}" -f $elapsed, $TimeoutSeconds, $stageText) -ForegroundColor DarkCyan
            $nextProgress += 10
        }

        if ($elapsed -ge $TimeoutSeconds) {
            $timedOut = $true
            Write-Host ''
            Write-Host ("Timeout reached at stage '{0}'. Stopping the isolated process tree." -f $lastStage) -ForegroundColor Yellow
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
finally {
    if (-not $process.HasExited) {
        try { Stop-ProcessTree -ProcessId $process.Id } catch {}
    }
    $process.Dispose()
}

[System.IO.File]::WriteAllText($stdoutPath, $stdout, [System.Text.UTF8Encoding]::new($true))
[System.IO.File]::WriteAllText($stderrPath, $stderr, [System.Text.UTF8Encoding]::new($true))

$workerParse = Convert-WorkerResult -Text $stdout
$workspaceAfter = Get-WorkspaceSnapshot -Path $workspacePath
$workspaceUnchanged = $workspaceBefore.metadata_sha256 -eq $workspaceAfter.metadata_sha256

$effectiveExitCode = $exitCode
$exitCodeSource = 'process_exit_code'
if ($null -eq $effectiveExitCode -and $null -ne $workerParse.value) {
    if ([string]$workerParse.value.status -eq 'passed_gpu_visible') {
        $effectiveExitCode = 0
    }
    else {
        $effectiveExitCode = 1
    }
    $exitCodeSource = 'inferred_from_complete_sentinel_json'
}
if ($null -eq $effectiveExitCode) {
    $effectiveExitCode = -1
    $exitCodeSource = 'unavailable'
}

$status = 'blocked_unknown'
if ($timedOut) {
    $status = 'blocked_timeout'
}
elif ($null -ne $workerParse.error) {
    $status = 'blocked_missing_or_invalid_sentinel_json'
}
elif (-not $workspaceUnchanged) {
    $status = 'blocked_workspace_changed'
}
elif ([string]$workerParse.value.status -eq 'passed_gpu_visible' -and [int]$effectiveExitCode -eq 0) {
    $status = 'passed'
}
else {
    $status = [string]$workerParse.value.status
}

$nvidiaSmi = [ordered]@{ exit_code = -1; output = 'nvidia-smi.exe was not found on PATH.' }
$nvidiaSmiCommand = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
if ($nvidiaSmiCommand) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nvidiaLines = @(& $nvidiaSmiCommand.Source --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader 2>&1 | ForEach-Object { $_.ToString() })
        $nvidiaSmi = [ordered]@{ exit_code = $LASTEXITCODE; output = ($nvidiaLines -join [Environment]::NewLine).Trim() }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'legacy_tensorflow_cuda_gpu_visibility_probe'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    preconditions = [ordered]@{
        antivirus_zero_risk_confirmed_by_user = [bool]$AntivirusScanConfirmed
        step9_report = $layoutReport.FullName
        step9_status = [string]$layout.status
    }
    runtime = [ordered]@{
        root = $runtimeRoot
        python_exe = $pythonExe
        deepfacelab_root = $deepFaceLabRoot
        main_py = $mainPy
        workspace = $workspacePath
    }
    isolation = [ordered]@{
        working_directory = $outputDirectory
        system_cuda_environment_cleared = $true
        pythonhome_cleared = $true
        pythonpath_cleared = $true
        isolated_path_entries = @($pathEntries)
        bundled_dll_file_count = $dllFiles.Count
        bundled_dlls = @($dllFiles | ForEach-Object { [ordered]@{ name = $_.Name; path = $_.FullName; size_bytes = [int64]$_.Length } })
    }
    process = [ordered]@{
        timeout_seconds = $TimeoutSeconds
        timed_out = $timedOut
        final_stage = $lastStage
        exit_code = $exitCode
        effective_exit_code = [int]$effectiveExitCode
        exit_code_source = $exitCodeSource
        sentinel_parse_error = $workerParse.error
        stdout_file = $stdoutPath
        stderr_file = $stderrPath
        stderr_tail = Limit-Text -Text $stderr
    }
    worker_result = $workerParse.value
    nvidia_smi = $nvidiaSmi
    workspace = [ordered]@{
        before = $workspaceBefore
        after = $workspaceAfter
        unchanged = $workspaceUnchanged
    }
    safety = [ordered]@{
        tensorflow_import_attempted = $true
        deepfacelab_main_imported = $false
        deepfacelab_main_executed = $false
        bundled_launcher_bat_executed = $false
        model_created = $false
        tensor_workload_executed = $false
        training_started = $false
        merge_started = $false
        dfm_export_started = $false
        workspace_modified_intentionally = $false
        timeout_process_tree_termination_enabled = $true
        note = 'This probe imports TensorFlow and enumerates devices only. It does not import or execute DeepFaceLab main.py and does not create tensors, models, checkpoints, merges, or exports.'
    }
    next_action = $(if ($status -eq 'passed') { 'Review the GPU visibility evidence, then prepare a tiny authorized non-public P0 dataset and a separate end-to-end test plan.' } else { 'Review captured stdout/stderr and worker_result before any extraction or training attempt.' })
}

$reportJson = $report | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($reportPath, $reportJson, [System.Text.UTF8Encoding]::new($true))

Write-Host ''
Write-Host '[3/4] TensorFlow/GPU visibility result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Timed out: {0}" -f $timedOut)
Write-Host ("Effective exit code: {0} ({1})" -f $effectiveExitCode, $exitCodeSource)
Write-Host ("Workspace unchanged: {0}" -f $workspaceUnchanged)
if ($null -ne $workerParse.value) {
    Write-Host ("TensorFlow imported: {0}" -f $workerParse.value.tensorflow_imported)
    Write-Host ("TensorFlow version: {0}" -f $workerParse.value.tensorflow.version)
    Write-Host ("Built with CUDA: {0}" -f $workerParse.value.tensorflow.built_with_cuda)
    Write-Host ("Physical GPU count: {0}" -f $workerParse.value.physical_gpu_count)
    Write-Host ("Local GPU count: {0}" -f $workerParse.value.local_gpu_count)
    Write-Host ("GPU device name: {0}" -f $workerParse.value.gpu_device_name)
}
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ("Stdout: {0}" -f $stdoutPath)
Write-Host ("Stderr: {0}" -f $stderrPath)
Write-Host ''
Write-Host '[4/4] Safety boundary' -ForegroundColor Cyan
Write-Host 'DeepFaceLab main.py, bundled launcher BAT files, models, tensors, and training were not started.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    timed_out = $timedOut
    effective_exit_code = [int]$effectiveExitCode
    workspace_unchanged = $workspaceUnchanged
    tensorflow_imported = $(if ($null -ne $workerParse.value) { [bool]$workerParse.value.tensorflow_imported } else { $false })
    tensorflow_version = $(if ($null -ne $workerParse.value) { [string]$workerParse.value.tensorflow.version } else { $null })
    physical_gpu_count = $(if ($null -ne $workerParse.value) { [int]$workerParse.value.physical_gpu_count } else { 0 })
    local_gpu_count = $(if ($null -ne $workerParse.value) { [int]$workerParse.value.local_gpu_count } else { 0 })
}

if ($status -ne 'passed') { exit 1 }
exit 0
