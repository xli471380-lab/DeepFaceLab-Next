[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$ProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$file = Get-Item -LiteralPath $resolvedPackage -Force

$machineId = $env:COMPUTERNAME.ToLowerInvariant()
$environmentId = 'defender-diagnostics'
if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
    $resolvedProfile = (Resolve-Path -LiteralPath $ProfilePath).Path
    $profile = Import-PowerShellDataFile -LiteralPath $resolvedProfile
    if ($profile.ContainsKey('MachineId') -and -not [string]::IsNullOrWhiteSpace([string]$profile.MachineId)) {
        $machineId = [string]$profile.MachineId
    }
    if ($profile.ContainsKey('EnvironmentId') -and -not [string]::IsNullOrWhiteSpace([string]$profile.EnvironmentId)) {
        $environmentId = [string]$profile.EnvironmentId
    }
}

function Find-DefenderCli {
    $platformRoot = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
    if (Test-Path -LiteralPath $platformRoot -PathType Container) {
        $latest = Get-ChildItem -LiteralPath $platformRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'MpCmdRun.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($latest) { return $latest }
    }

    $legacy = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (Test-Path -LiteralPath $legacy -PathType Leaf) {
        return (Resolve-Path -LiteralPath $legacy).Path
    }
    return $null
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
        $exitCode = $LASTEXITCODE
        return [ordered]@{
            exit_code = $exitCode
            exit_code_hex = ('0x{0:X8}' -f ([uint32]$exitCode))
            output = ($lines -join [Environment]::NewLine).Trim()
        }
    }
    catch {
        return [ordered]@{
            exit_code = -1
            exit_code_hex = '0xFFFFFFFF'
            output = $_.Exception.Message
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$timestamp = (Get-Date).ToUniversalTime()
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\defender-diagnostics" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$reportPath = Join-Path $outputDirectory ("defender-scan-diagnostics-{0}.json" -f $fileTimestamp)
$logPath = Join-Path $outputDirectory ("defender-scan-diagnostics-{0}.txt" -f $fileTimestamp)

$log = New-Object System.Collections.ArrayList
[void]$log.Add("Package: $resolvedPackage")
[void]$log.Add("Administrator: $isAdministrator")

$status = $null
$statusError = $null
$statusCommand = Get-Command 'Get-MpComputerStatus' -ErrorAction SilentlyContinue
if ($null -ne $statusCommand) {
    try {
        $rawStatus = Get-MpComputerStatus -ErrorAction Stop
        $status = [ordered]@{
            am_running_mode = $rawStatus.AMRunningMode
            am_service_enabled = $rawStatus.AMServiceEnabled
            antivirus_enabled = $rawStatus.AntivirusEnabled
            antispyware_enabled = $rawStatus.AntispywareEnabled
            real_time_protection_enabled = $rawStatus.RealTimeProtectionEnabled
            behavior_monitor_enabled = $rawStatus.BehaviorMonitorEnabled
            ioav_protection_enabled = $rawStatus.IoavProtectionEnabled
            nis_enabled = $rawStatus.NISEnabled
            antivirus_signature_version = $rawStatus.AntivirusSignatureVersion
            antivirus_signature_last_updated = $rawStatus.AntivirusSignatureLastUpdated
            am_engine_version = $rawStatus.AMEngineVersion
            am_product_version = $rawStatus.AMProductVersion
        }
        [void]$log.Add(('Defender mode: {0}' -f $rawStatus.AMRunningMode))
        [void]$log.Add(('AntivirusEnabled={0}; RealTimeProtectionEnabled={1}; AMServiceEnabled={2}' -f $rawStatus.AntivirusEnabled, $rawStatus.RealTimeProtectionEnabled, $rawStatus.AMServiceEnabled))
    }
    catch {
        $statusError = $_.Exception.Message
        [void]$log.Add("Get-MpComputerStatus failed: $statusError")
    }
}
else {
    $statusError = 'Get-MpComputerStatus is not available.'
    [void]$log.Add($statusError)
}

$providers = @()
try {
    $providers = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction Stop | ForEach-Object {
        [ordered]@{
            display_name = $_.displayName
            product_state = $_.productState
            path_to_signed_product_exe = $_.pathToSignedProductExe
            path_to_signed_reporting_exe = $_.pathToSignedReportingExe
        }
    })
    foreach ($provider in $providers) {
        [void]$log.Add(('Security provider: {0}; state={1}' -f $provider.display_name, $provider.product_state))
    }
}
catch {
    [void]$log.Add(('SecurityCenter2 provider query failed: {0}' -f $_.Exception.Message))
}

$startMpScan = [ordered]@{
    available = $false
    attempted = $false
    success = $false
    error_message = $null
    error_type = $null
    fully_qualified_error_id = $null
    category_info = $null
    hresult_decimal = $null
    hresult_hex = $null
}

$scanStart = Get-Date
$startMpScanCommand = Get-Command 'Start-MpScan' -ErrorAction SilentlyContinue
if ($null -ne $startMpScanCommand) {
    $startMpScan.available = $true
    $startMpScan.attempted = $true
    try {
        [void]$log.Add('Starting Start-MpScan custom scan...')
        Start-MpScan -ScanType CustomScan -ScanPath $resolvedPackage -ErrorAction Stop
        $startMpScan.success = $true
        [void]$log.Add('Start-MpScan completed without an exception.')
    }
    catch {
        $exception = $_.Exception
        $startMpScan.error_message = $exception.Message
        $startMpScan.error_type = $exception.GetType().FullName
        $startMpScan.fully_qualified_error_id = $_.FullyQualifiedErrorId
        $startMpScan.category_info = $_.CategoryInfo.ToString()
        $startMpScan.hresult_decimal = $exception.HResult
        $startMpScan.hresult_hex = ('0x{0:X8}' -f ([uint32]$exception.HResult))
        [void]$log.Add(('Start-MpScan failed: {0}' -f $exception.Message))
        [void]$log.Add(('Error type: {0}; FQID: {1}; HResult: {2}' -f $startMpScan.error_type, $startMpScan.fully_qualified_error_id, $startMpScan.hresult_hex))
    }
}
else {
    [void]$log.Add('Start-MpScan is not available.')
}

$mpCmdRun = [ordered]@{
    available = $false
    path = $null
    attempted = $false
    exit_code = $null
    exit_code_hex = $null
    output = $null
}

if (-not $startMpScan.success) {
    $defenderCli = Find-DefenderCli
    if ($defenderCli) {
        $mpCmdRun.available = $true
        $mpCmdRun.path = $defenderCli
        $mpCmdRun.attempted = $true
        [void]$log.Add("Running MpCmdRun fallback: $defenderCli")
        $result = Invoke-NativeCapture -Executable $defenderCli -Arguments @('-Scan', '-ScanType', '3', '-File', $resolvedPackage, '-ReturnHR')
        $mpCmdRun.exit_code = $result.exit_code
        $mpCmdRun.exit_code_hex = $result.exit_code_hex
        $mpCmdRun.output = $result.output
        [void]$log.Add(('MpCmdRun exit code: {0} ({1})' -f $result.exit_code, $result.exit_code_hex))
        [void]$log.Add($result.output)
    }
    else {
        [void]$log.Add('MpCmdRun.exe was not found.')
    }
}

$matchingDetections = @()
$threatCommand = Get-Command 'Get-MpThreatDetection' -ErrorAction SilentlyContinue
if ($null -ne $threatCommand) {
    try {
        $matchingDetections = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object {
            $resources = @($_.Resources)
            @($resources | Where-Object { [string]$_ -like "*$resolvedPackage*" }).Count -gt 0 -or
            ($_.InitialDetectionTime -and $_.InitialDetectionTime -ge $scanStart.AddMinutes(-1))
        } | ForEach-Object {
            [ordered]@{
                threat_id = $_.ThreatID
                threat_status_id = $_.ThreatStatusID
                initial_detection_time = $_.InitialDetectionTime
                last_threat_status_change_time = $_.LastThreatStatusChangeTime
                resources = @($_.Resources)
            }
        })
    }
    catch {
        [void]$log.Add(('Get-MpThreatDetection failed: {0}' -f $_.Exception.Message))
    }
}

$success = $startMpScan.success -or ($mpCmdRun.attempted -and $mpCmdRun.exit_code -eq 0)
$statusSummary = if ($success) {
    'scan_completed'
}
elseif ($status -and $status.am_running_mode -notmatch 'Normal') {
    'defender_not_active'
}
elseif (-not $isAdministrator) {
    'retry_as_administrator'
}
else {
    'scan_failed'
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    machine_id = $machineId
    environment_id = $environmentId
    package = [ordered]@{
        path = $resolvedPackage
        size_bytes = [int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $resolvedPackage -Algorithm SHA256).Hash
    }
    administrator = $isAdministrator
    defender_status = $status
    defender_status_error = $statusError
    security_providers = @($providers)
    start_mpscan = $startMpScan
    mpcmdrun = $mpCmdRun
    matching_detection_count = @($matchingDetections).Count
    matching_detections = @($matchingDetections)
    success = $success
    status = $statusSummary
    safety_note = 'This tool reads antivirus status and requests a custom scan. It does not change Defender settings, exclusions, services, or the downloaded package.'
}

@($log) | Set-Content -LiteralPath $logPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Defender scan diagnostics completed.' -ForegroundColor Green
Write-Host ("Administrator: {0}" -f $isAdministrator)
if ($status) {
    Write-Host ("AMRunningMode: {0}" -f $status.am_running_mode)
    Write-Host ("AntivirusEnabled: {0}" -f $status.antivirus_enabled)
    Write-Host ("RealTimeProtectionEnabled: {0}" -f $status.real_time_protection_enabled)
}
Write-Host ("Start-MpScan success: {0}" -f $startMpScan.success)
if ($startMpScan.error_message) {
    Write-Host ("Start-MpScan error: {0}" -f $startMpScan.error_message) -ForegroundColor Yellow
}
if ($mpCmdRun.attempted) {
    Write-Host ("MpCmdRun exit: {0} ({1})" -f $mpCmdRun.exit_code, $mpCmdRun.exit_code_hex)
}
Write-Host ("Matching detections: {0}" -f @($matchingDetections).Count)
Write-Host ("Status: {0}" -f $statusSummary)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ("Log: {0}" -f $logPath)

[PSCustomObject]@{
    report_path = $reportPath
    log_path = $logPath
    status = $statusSummary
    success = $success
    administrator = $isAdministrator
    am_running_mode = $(if ($status) { $status.am_running_mode } else { $null })
}
