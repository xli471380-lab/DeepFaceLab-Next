[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RuntimeRoot,
    [string]$ProfilePath,
    [string]$MachineId = 'hp-a2000',
    [string]$EnvironmentId = 'legacy-dfl-rtx3000-20211120'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runtimeRootResolved = (Resolve-Path -LiteralPath $RuntimeRoot).Path

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path $repoRoot 'config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1'
}

$profileFull = [System.IO.Path]::GetFullPath($ProfilePath)
$localConfigRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'config\local')).TrimEnd('\')
if (-not $profileFull.StartsWith($localConfigRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'ProfilePath must be inside config\local so machine-specific paths remain ignored by Git.'
}

$internalRoot = Join-Path $runtimeRootResolved '_internal'
$pythonExe = Join-Path $internalRoot 'python-3.6.8\python.exe'
$ffmpegExe = Join-Path $internalRoot 'ffmpeg\ffmpeg.exe'
$deepFaceLabRoot = Join-Path $internalRoot 'DeepFaceLab'
$mainPy = Join-Path $deepFaceLabRoot 'main.py'
$workspacePath = Join-Path $runtimeRootResolved 'workspace'

$requiredPaths = [ordered]@{
    runtime_root = $runtimeRootResolved
    internal_root = $internalRoot
    python_exe = $pythonExe
    ffmpeg_exe = $ffmpegExe
    deepfacelab_root = $deepFaceLabRoot
    main_py = $mainPy
    workspace = $workspacePath
}

$missing = @()
foreach ($entry in $requiredPaths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        $missing += ("{0}: {1}" -f $entry.Key, $entry.Value)
    }
}
if ($missing.Count -gt 0) {
    throw ('Required legacy runtime paths are missing: ' + ($missing -join '; '))
}

function Escape-Psd1String {
    param([AllowEmptyString()][string]$Value)
    return $Value.Replace("'", "''")
}

$profileDirectory = Split-Path -Parent $profileFull
New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null

$profileCreated = $false
if (-not (Test-Path -LiteralPath $profileFull -PathType Leaf)) {
    $profileText = @"
@{
    SchemaVersion = 2
    MachineId = '$(Escape-Psd1String $MachineId)'
    EnvironmentId = '$(Escape-Psd1String $EnvironmentId)'
    Role = 'full-development'
    PythonExe = '$(Escape-Psd1String $pythonExe)'
    FFmpegExe = '$(Escape-Psd1String $ffmpegExe)'
    NvccExe = ''
    RuntimeRoot = '$(Escape-Psd1String $runtimeRootResolved)'
    DeepFaceLabRoot = '$(Escape-Psd1String $deepFaceLabRoot)'
    MainPy = '$(Escape-Psd1String $mainPy)'
    WorkspacePath = '$(Escape-Psd1String $workspacePath)'
    Notes = 'Historical NVIDIA RTX 3000 DeepFaceLab build dated 2021-11-20. Profile and runtime artifacts remain local and untracked.'
}
"@
    $profileText | Set-Content -LiteralPath $profileFull -Encoding UTF8
    $profileCreated = $true
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        return [ordered]@{
            exit_code = $LASTEXITCODE
            output = ($lines -join [Environment]::NewLine).Trim()
        }
    }
    catch {
        return [ordered]@{
            exit_code = -1
            output = $_.Exception.ToString()
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

$timestamp = (Get-Date).ToUniversalTime()
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\runtime-probe" -f $MachineId, $EnvironmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$reportPath = Join-Path $outputDirectory ("legacy-runtime-readonly-probe-{0}.json" -f $fileTimestamp)
$pipListPath = Join-Path $outputDirectory ("legacy-runtime-pip-list-{0}.json" -f $fileTimestamp)

$pythonVersion = Invoke-NativeCapture -Executable $pythonExe -Arguments @('--version')
$pythonIdentity = Invoke-NativeCapture -Executable $pythonExe -Arguments @('-c', 'import sys;print(sys.executable);print(sys.version.replace(chr(10),chr(32)).replace(chr(13),chr(32)))')
$pipList = Invoke-NativeCapture -Executable $pythonExe -Arguments @('-m', 'pip', 'list', '--format=json', '--disable-pip-version-check')
if (-not [string]::IsNullOrWhiteSpace($pipList.output)) {
    $pipList.output | Set-Content -LiteralPath $pipListPath -Encoding UTF8
}

$ffmpegVersion = Invoke-NativeCapture -Executable $ffmpegExe -Arguments @('-version')
$nvidiaSmiCommand = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
$nvidiaSmi = if ($nvidiaSmiCommand) {
    Invoke-NativeCapture -Executable $nvidiaSmiCommand.Source -Arguments @('--query-gpu=name,driver_version,memory.total,compute_cap', '--format=csv,noheader')
}
else {
    [ordered]@{ exit_code = -1; output = 'nvidia-smi.exe was not found on PATH.' }
}

$selectedPackages = @()
if ($pipList.exit_code -eq 0) {
    try {
        $allPackages = @($pipList.output | ConvertFrom-Json)
        $wanted = @('numpy','h5py','opencv-python','scipy','tensorflow','tensorflow-gpu','tf2onnx','onnx','keras')
        $selectedPackages = @($allPackages | Where-Object { $wanted -contains $_.name.ToLowerInvariant() } | Sort-Object name)
    }
    catch {
        $selectedPackages = @()
    }
}

$cudaDllPatterns = @('cudart64*.dll','cudnn64*.dll','cublas64*.dll','cublasLt64*.dll','nvrtc64*.dll','cusolver64*.dll','cusparse64*.dll')
$cudaDlls = @()
foreach ($pattern in $cudaDllPatterns) {
    $cudaDlls += @(Get-ChildItem -LiteralPath $internalRoot -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Name, Length, LastWriteTime)
}
$cudaDlls = @($cudaDlls | Sort-Object FullName -Unique)

$pythonInfo = Get-Item -LiteralPath $pythonExe
$ffmpegInfo = Get-Item -LiteralPath $ffmpegExe
$mainInfo = Get-Item -LiteralPath $mainPy

$status = if ($pythonVersion.exit_code -eq 0 -and $pythonIdentity.exit_code -eq 0 -and $ffmpegVersion.exit_code -eq 0) {
    'passed'
}
else {
    'blocked'
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'legacy_runtime_readonly_probe'
    status = $status
    machine_id = $MachineId
    environment_id = $EnvironmentId
    profile = [ordered]@{
        path = $profileFull
        created = $profileCreated
        git_ignored_local_path = $true
    }
    runtime = [ordered]@{
        root = $runtimeRootResolved
        internal_root = $internalRoot
        deepfacelab_root = $deepFaceLabRoot
        main_py = $mainPy
        workspace = $workspacePath
    }
    python = [ordered]@{
        path = $pythonExe
        file_version = $pythonInfo.VersionInfo.FileVersion
        product_version = $pythonInfo.VersionInfo.ProductVersion
        version_exit_code = $pythonVersion.exit_code
        version_output = $pythonVersion.output
        identity_exit_code = $pythonIdentity.exit_code
        identity_output = $pythonIdentity.output
        pip_list_exit_code = $pipList.exit_code
        pip_list_file = $(if (Test-Path -LiteralPath $pipListPath) { $pipListPath } else { $null })
        selected_packages = @($selectedPackages)
    }
    ffmpeg = [ordered]@{
        path = $ffmpegExe
        file_version = $ffmpegInfo.VersionInfo.FileVersion
        product_version = $ffmpegInfo.VersionInfo.ProductVersion
        version_exit_code = $ffmpegVersion.exit_code
        version_output = $ffmpegVersion.output
    }
    deepfacelab_main = [ordered]@{
        path = $mainPy
        size_bytes = [int64]$mainInfo.Length
        last_write_time = $mainInfo.LastWriteTime
        executed = $false
    }
    nvidia_smi = $nvidiaSmi
    bundled_cuda_dlls = @($cudaDlls)
    safety = [ordered]@{
        main_py_executed = $false
        training_started = $false
        workspace_modified_intentionally = $false
        note = 'This probe only runs the embedded Python interpreter, pip package listing, FFmpeg version command, and nvidia-smi. It does not start DeepFaceLab main.py or training.'
    }
    next_action = 'Review versions and bundled CUDA libraries, then run a separate controlled import/GPU probe before using authorized test media.'
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Legacy runtime read-only probe completed.' -ForegroundColor Green
Write-Host ("Status: {0}" -f $status)
Write-Host ("Profile: {0}" -f $profileFull)
Write-Host ("Profile created: {0}" -f $profileCreated)
Write-Host ("Python: {0}" -f $pythonVersion.output)
Write-Host ("FFmpeg exit code: {0}" -f $ffmpegVersion.exit_code)
Write-Host ("Selected package records: {0}" -f @($selectedPackages).Count)
Write-Host ("Bundled CUDA DLL records: {0}" -f @($cudaDlls).Count)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ''
Write-Host 'DeepFaceLab main.py was not executed.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    profile_path = $profileFull
    status = $status
    python_version = $pythonVersion.output
    ffmpeg_exit_code = $ffmpegVersion.exit_code
    selected_package_count = @($selectedPackages).Count
    cuda_dll_count = @($cudaDlls).Count
}

if ($status -ne 'passed') {
    exit 1
}
exit 0
