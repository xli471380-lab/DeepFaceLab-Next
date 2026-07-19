[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$PythonExe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'artifacts\p0'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Get-CommandResult {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @()
    )

    $resolved = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        return [ordered]@{
            available = $false
            command   = $Command
            path      = $null
            exit_code = $null
            output    = $null
        }
    }

    try {
        $output = & $resolved.Source @Arguments 2>&1 | Out-String
        return [ordered]@{
            available = $true
            command   = $Command
            path      = $resolved.Source
            exit_code = $LASTEXITCODE
            output    = $output.Trim()
        }
    }
    catch {
        return [ordered]@{
            available = $true
            command   = $Command
            path      = $resolved.Source
            exit_code = -1
            output    = $_.Exception.Message
        }
    }
}

function Get-ExplicitExecutableResult {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        return [ordered]@{
            available = $false
            command   = $Executable
            path      = $Executable
            exit_code = $null
            output    = $null
        }
    }

    try {
        $output = & $Executable @Arguments 2>&1 | Out-String
        return [ordered]@{
            available = $true
            command   = $Executable
            path      = (Resolve-Path -LiteralPath $Executable).Path
            exit_code = $LASTEXITCODE
            output    = $output.Trim()
        }
    }
    catch {
        return [ordered]@{
            available = $true
            command   = $Executable
            path      = $Executable
            exit_code = -1
            output    = $_.Exception.Message
        }
    }
}

function Get-GitText {
    param([string[]]$Arguments)

    try {
        return (& git -C $repoRoot @Arguments 2>&1 | Out-String).Trim()
    }
    catch {
        return $null
    }
}

$warnings = New-Object System.Collections.Generic.List[string]

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$videoControllers = Get-CimInstance Win32_VideoController | ForEach-Object {
    [ordered]@{
        name           = $_.Name
        driver_version = $_.DriverVersion
        adapter_ram    = $_.AdapterRAM
        status         = $_.Status
    }
}

$nvidiaSmi = Get-CommandResult -Command 'nvidia-smi' -Arguments @(
    '--query-gpu=index,name,driver_version,memory.total,memory.used,memory.free,compute_cap',
    '--format=csv,noheader,nounits'
)
if (-not $nvidiaSmi.available) {
    $warnings.Add('nvidia-smi was not found. NVIDIA runtime details could not be verified.')
}

$gitVersion = Get-CommandResult -Command 'git' -Arguments @('--version')
if (-not $gitVersion.available) {
    $warnings.Add('Git was not found on PATH.')
}

$ffmpegVersion = Get-CommandResult -Command 'ffmpeg' -Arguments @('-version')
if (-not $ffmpegVersion.available) {
    $warnings.Add('FFmpeg was not found on PATH.')
}

$nvccVersion = Get-CommandResult -Command 'nvcc' -Arguments @('--version')
if (-not $nvccVersion.available) {
    $warnings.Add('nvcc was not found on PATH. This may be expected for a bundled runtime.')
}

$pythonResult = $null
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
    $pythonResult = Get-ExplicitExecutableResult -Executable $PythonExe -Arguments @(
        '-c',
        'import json,platform,sys; print(json.dumps({"executable":sys.executable,"version":sys.version,"platform":platform.platform()}))'
    )
    if (-not $pythonResult.available -or $pythonResult.exit_code -ne 0) {
        $warnings.Add('The explicitly supplied Python executable could not be verified.')
    }
}
else {
    $pythonResult = Get-CommandResult -Command 'python' -Arguments @(
        '-c',
        'import json,platform,sys; print(json.dumps({"executable":sys.executable,"version":sys.version,"platform":platform.platform()}))'
    )
    if (-not $pythonResult.available) {
        $warnings.Add('Python was not found on PATH. Supply -PythonExe when using a bundled interpreter.')
    }
}

$pythonLauncher = Get-CommandResult -Command 'py' -Arguments @('-0p')

$environmentNames = @(
    'CUDA_PATH',
    'CUDA_PATH_V12_0',
    'CUDA_PATH_V13_0',
    'CUDNN_PATH',
    'TENSORRT_ROOT',
    'CONDA_PREFIX',
    'VIRTUAL_ENV',
    'TF_FORCE_GPU_ALLOW_GROWTH'
)
$environment = [ordered]@{}
foreach ($name in $environmentNames) {
    $environment[$name] = [Environment]::GetEnvironmentVariable($name)
}

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputPath = Join-Path $OutputDirectory ("system-diagnostics-{0}.json" -f $fileTimestamp)

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    status = 'diagnostic_complete'
    repository = [ordered]@{
        root = $repoRoot
        remote = Get-GitText -Arguments @('remote', 'get-url', 'origin')
        branch = Get-GitText -Arguments @('branch', '--show-current')
        commit = Get-GitText -Arguments @('rev-parse', 'HEAD')
        status_porcelain = Get-GitText -Arguments @('status', '--porcelain')
    }
    windows = [ordered]@{
        caption = $os.Caption
        version = $os.Version
        build_number = $os.BuildNumber
        architecture = $os.OSArchitecture
        powershell_version = $PSVersionTable.PSVersion.ToString()
    }
    hardware = [ordered]@{
        manufacturer = $computer.Manufacturer
        model = $computer.Model
        total_physical_memory_bytes = [int64]$computer.TotalPhysicalMemory
        cpu = [ordered]@{
            name = $cpu.Name
            cores = $cpu.NumberOfCores
            logical_processors = $cpu.NumberOfLogicalProcessors
        }
        video_controllers = @($videoControllers)
    }
    tools = [ordered]@{
        git = $gitVersion
        ffmpeg = $ffmpegVersion
        nvcc = $nvccVersion
        nvidia_smi = $nvidiaSmi
        python = $pythonResult
        python_launcher = $pythonLauncher
    }
    environment = $environment
    warnings = @($warnings)
    privacy_note = 'Review this local report before sharing because executable and environment paths may contain usernames or private directory names.'
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

Write-Host ''
Write-Host 'DeepFaceLab-Next P0 system diagnostics completed.' -ForegroundColor Green
Write-Host ("Report: {0}" -f $outputPath)
if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host ("- {0}" -f $warning) -ForegroundColor Yellow
    }
}

[PSCustomObject]@{
    report_path = $outputPath
    warning_count = $warnings.Count
    commit = $report.repository.commit
    branch = $report.repository.branch
}
