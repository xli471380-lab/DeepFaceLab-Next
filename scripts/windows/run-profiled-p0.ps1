[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [switch]$DiagnosticsOnly,
    [switch]$AllowDirtyTree
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profilePathResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profilePathResolved

function Read-ProfileValue([string]$Name, [bool]$Required) {
    if (-not $profile.ContainsKey($Name)) {
        if ($Required) { throw "Missing profile key: $Name" }
        return $null
    }
    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($Required) { throw "Empty profile value: $Name" }
        return $null
    }
    return $value
}

$machineId = Read-ProfileValue 'MachineId' $true
$environmentId = Read-ProfileValue 'EnvironmentId' $true
$role = Read-ProfileValue 'Role' $true
$pythonExe = Read-ProfileValue 'PythonExe' $false
$ffmpegExe = Read-ProfileValue 'FFmpegExe' $false
$nvccExe = Read-ProfileValue 'NvccExe' $false
$notes = Read-ProfileValue 'Notes' $false

if ($machineId -notmatch '^[A-Za-z0-9._-]+$' -or $environmentId -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'MachineId and EnvironmentId contain invalid characters.'
}
if ($role -notin @('engineering','baseline','performance')) {
    throw 'Role must be engineering, baseline, or performance.'
}
foreach ($item in @(@('PythonExe',$pythonExe),@('FFmpegExe',$ffmpegExe),@('NvccExe',$nvccExe))) {
    if ($item[1] -and -not (Test-Path -LiteralPath $item[1] -PathType Leaf)) {
        throw ("{0} does not exist: {1}" -f $item[0], $item[1])
    }
}

$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}" -f $machineId,$environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$timestamp = (Get-Date).ToUniversalTime()
$manifestPath = Join-Path $outputDirectory ("profile-manifest-{0}.json" -f $timestamp.ToString('yyyyMMddTHHmmssZ'))
[ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    machine_id = $machineId
    environment_id = $environmentId
    role = $role
    profile_file = $profilePathResolved
    tools = [ordered]@{ python_exe=$pythonExe; ffmpeg_exe=$ffmpegExe; nvcc_exe=$nvccExe }
    notes = $notes
    privacy_note = 'This ignored local manifest can contain private paths.'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$originalPath = $env:PATH
try {
    $dirs = @($ffmpegExe,$nvccExe) | Where-Object { $_ } | ForEach-Object { Split-Path -Parent $_ } | Select-Object -Unique
    if (@($dirs).Count -gt 0) { $env:PATH = ((@($dirs)+@($originalPath)) -join ';') }
    $scriptPath = if ($DiagnosticsOnly) { Join-Path $PSScriptRoot 'system-diagnostics.ps1' } else { Join-Path $PSScriptRoot 'p0-acceptance.ps1' }
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,'-OutputDirectory',$outputDirectory)
    if ($pythonExe) { $args += @('-PythonExe',$pythonExe) }
    if (-not $DiagnosticsOnly -and $AllowDirtyTree) { $args += '-AllowDirtyTree' }
    Write-Host "Machine: $machineId | Environment: $environmentId | Role: $role" -ForegroundColor Cyan
    Write-Host "Artifacts: $outputDirectory"
    & powershell.exe @args
    $exitCode = $LASTEXITCODE
}
finally { $env:PATH = $originalPath }
Write-Host "Profile manifest: $manifestPath"
exit $exitCode
