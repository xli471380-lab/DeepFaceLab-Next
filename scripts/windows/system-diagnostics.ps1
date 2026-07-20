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

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 can turn native stderr into ErrorRecord objects.
        # Continue locally so the complete stdout/stderr stream and exit code are retained.
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE

        return [ordered]@{
            exit_code = $exitCode
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

    $captured = Invoke-NativeCapture -Executable $resolved.Source -Arguments $Arguments
    return [ordered]@{
        available = $true
        command   = $Command
        path      = $resolved.Source
        exit_code = $captured.exit_code
        output    = $captured.output
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

    $resolvedPath = (Resolve-Path -LiteralPath $Executable).Path
    $captured = Invoke-NativeCapture -Executable $resolvedPath -Arguments $Arguments
    return [ordered]@{
        available = $true
        command   = $Executable
        path      = $resolvedPath
        exit_code = $captured.exit_code
        output    = $captured.output
    }
}

function Get-GitText {
    param([string[]]$Arguments)

    try {
        $captured = Invoke-NativeCapture -Executable 'git' -Arguments (@('-C', $repoRoot) + $Arguments)
        if ($captured.exit_code -ne 0) {
            return $null
        }
        return $captured.output
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
if (-not $nvidiaSmi.available -or $nvidiaSmi.exit_code -ne 0) {
    $warnings.Add('nvidia-smi could not be verified. NVIDIA runtime details may be incomplete.')
}

$gitVersion = Get-CommandResult -Command 'git' -Arguments @('--version')
if (-not $gitVersion.available -or $gitVersion.exit_code -ne 0) {
    $warnings.Add('Git could not be verified.')
}

$ffmpegVersion = Get-CommandResult -Command 'ffmpeg' -Arguments @('-version')
if (-not $ffmpegVersion.available) {
    $warnings.Add('FFmpeg was not found on PATH.')
}
elseif ($ffmpegVersion.exit_code -ne 0) {
    $warnings.Add('FFmpeg was found but did not run successfully.')
}

$nvccVersion = Get-CommandResult -Command 'nvcc' -Arguments @('--version')
if (-not $nvccVersion.available) {
    $warnings.Add('nvcc was not found on PATH. This may be expected for a bundled runtime.')
}
elseif ($nvccVersion.exit_code -ne 0) {
    $warnings.Add('nvcc was found but did not run successfully.')
}

$pythonArguments = @(
    '-c',
    'import platform,sys; print(sys.executable); print(sys.version.replace(chr(10), " ")); print(platform.platform())'
)

$pythonResult = $null
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
    $pythonResult = Get-ExplicitExecutableResult -Executable $PythonExe -Arguments $pythonArguments
    if (-not $pythonResult.available -or $pythonResult.exit_code -ne 0) {
        $warnings.Add('The explicitly supplied Python executable could not be verified. See the captured output for details.')
    }
}
else {
    $pythonResult = Get-CommandResult -Command 'python' -Arguments $pythonArguments
    if (-not $pythonResult.available) {
        $warnings.Add('Python was not found on PATH. Supply -PythonExe when using a bundled interpreter.')
    }
    elseif ($pythonResult.exit_code -ne 0) {
        $warnings.Add('Python was found but the runtime probe failed. See the captured output for details.')
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
    schema_version = 2
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
