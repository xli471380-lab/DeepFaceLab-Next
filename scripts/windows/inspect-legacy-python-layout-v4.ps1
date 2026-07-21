[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [string]$ProgressPath,
    [ValidateRange(5, 300)][int]$PythonProbeTimeoutSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$v3Script = Join-Path $PSScriptRoot 'inspect-legacy-python-layout-v3.ps1'
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved

function Write-Stage {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($ProgressPath)) { return }

    [ordered]@{
        updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        stage = $Stage
        message = $Message
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ProgressPath -Encoding UTF8
}

function Get-RequiredProfileValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $profile.ContainsKey($Name)) { throw "Missing profile key: $Name" }
    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Empty profile value: $Name" }
    return $value
}

if (-not (Test-Path -LiteralPath $v3Script -PathType Leaf)) {
    throw "Version 3 inspection script was not found: $v3Script"
}

$machineId = Get-RequiredProfileValue 'MachineId'
$environmentId = Get-RequiredProfileValue 'EnvironmentId'
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\python-layout-inspection" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$startedAt = Get-Date
Write-Stage -Stage 'compatibility-run-v3' -Message 'Running the compact v3 inspection before applying strict PowerShell 5.1 exit-code normalization.'

$innerOutput = @(
    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $v3Script `
        -ProfilePath $profileResolved `
        -ProgressPath $ProgressPath `
        -PythonProbeTimeoutSeconds $PythonProbeTimeoutSeconds `
        2>&1 | ForEach-Object { $_.ToString() }
)
$innerExitCode = if ($null -eq $LASTEXITCODE) { -999 } else { [int]$LASTEXITCODE }

$sourceReport = Get-ChildItem `
    -LiteralPath $outputDirectory `
    -Filter 'legacy-python-layout-inspection-*.json' `
    -File `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $startedAt.AddSeconds(-2) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $sourceReport) {
    if ($innerOutput.Count -gt 0) { Write-Host ($innerOutput -join [Environment]::NewLine) }
    throw 'The v3 inspection did not create a JSON report.'
}

$report = Get-Content -LiteralPath $sourceReport.FullName -Raw -ErrorAction Stop | ConvertFrom-Json

if ([string]$report.status -eq 'passed' -and $innerExitCode -eq 0) {
    Write-Host ($innerOutput -join [Environment]::NewLine)
    exit 0
}

$normal = $report.python_path.normal
$noSite = $report.python_path.without_site

$normalExitMissing = $null -eq $normal.exit_code
$noSiteExitMissing = $null -eq $noSite.exit_code

$normalEvidenceComplete = (
    -not [bool]$normal.timed_out -and
    $null -eq $normal.parse_error -and
    $null -ne $normal.data -and
    [bool]$normal.site_packages_visible -and
    [int]$normal.data.no_site -eq 0
)

$noSiteEvidenceComplete = (
    -not [bool]$noSite.timed_out -and
    $null -eq $noSite.parse_error -and
    $null -ne $noSite.data -and
    [int]$noSite.data.no_site -eq 1
)

$filesystemEvidenceComplete = (
    [int]$report.filesystem.site_packages_top_level_count -gt 0 -and
    [int]$report.filesystem.selected_artifact_group_count -gt 0 -and
    [int]$report.launchers.top_level_bat_count -gt 0
)

$warningCount = @($report.warnings).Count
$eligibleForNormalization = (
    [string]$report.status -eq 'blocked' -and
    ($normalExitMissing -or [int]$normal.exit_code -eq 0) -and
    ($noSiteExitMissing -or [int]$noSite.exit_code -eq 0) -and
    $normalEvidenceComplete -and
    $noSiteEvidenceComplete -and
    $filesystemEvidenceComplete -and
    $warningCount -eq 0
)

if (-not $eligibleForNormalization) {
    if ($innerOutput.Count -gt 0) { Write-Host ($innerOutput -join [Environment]::NewLine) }
    Write-Host ''
    Write-Host 'The report was not eligible for exit-code normalization.' -ForegroundColor Yellow
    Write-Host ("Source report: {0}" -f $sourceReport.FullName)
    Write-Host ("Inner exit code: {0}" -f $innerExitCode)
    exit $(if ($innerExitCode -eq 0) { 1 } else { $innerExitCode })
}

Write-Stage -Stage 'compatibility-normalization' -Message 'Complete sentinel JSON evidence was found; normalizing missing PowerShell 5.1 native exit codes to zero.'

if ($normalExitMissing) {
    $normal.exit_code = 0
    $normal | Add-Member -NotePropertyName exit_code_source -NotePropertyValue 'inferred_from_complete_sentinel_json' -Force
}
if ($noSiteExitMissing) {
    $noSite.exit_code = 0
    $noSite | Add-Member -NotePropertyName exit_code_source -NotePropertyValue 'inferred_from_complete_sentinel_json' -Force
}

$sourceStatus = [string]$report.status
$report.schema_version = 4
$report.status = 'passed'
$report | Add-Member -NotePropertyName compatibility -NotePropertyValue ([pscustomobject][ordered]@{
    powershell_version = $PSVersionTable.PSVersion.ToString()
    source_report = $sourceReport.FullName
    source_status = $sourceStatus
    source_process_exit_code = $innerExitCode
    normalized_missing_native_exit_codes = $true
    rule = 'Only normalize a missing exit code when the probe did not time out, sentinel JSON parsed completely, normal/no-site flags are correct, site-packages is visible in normal mode, selected artifacts exist, launcher BAT files exist, and there are zero warnings.'
}) -Force
$report.next_action = 'Proceed to a separate controlled TensorFlow, bundled CUDA DLL, and GPU visibility probe; do not start training yet.'

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$reportPath = Join-Path $outputDirectory ("legacy-python-layout-inspection-v4-{0}.json" -f $timestamp)
$reportJson = $report | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($reportPath, $reportJson, [System.Text.UTF8Encoding]::new($true))

Write-Stage -Stage 'complete' -Message 'The schema v4 report passed after strict PowerShell 5.1 missing-exit-code normalization.'

Write-Host ''
Write-Host 'Legacy Python layout inspection v4 completed.' -ForegroundColor Green
Write-Host 'Status: passed'
Write-Host ("Normal Python probe timed out: {0}; exit code: {1}; source: {2}" -f $normal.timed_out, $normal.exit_code, $normal.exit_code_source)
Write-Host ("Python -S probe timed out: {0}; exit code: {1}; source: {2}" -f $noSite.timed_out, $noSite.exit_code, $noSite.exit_code_source)
Write-Host ("Default sys.path includes site-packages: {0}" -f $normal.site_packages_visible)
Write-Host ("Without-site sys.path includes site-packages: {0}" -f $noSite.site_packages_visible)
Write-Host ("site-packages top-level items: {0}" -f $report.filesystem.site_packages_top_level_count)
Write-Host ("dist-info/egg-info directories: {0}" -f $report.filesystem.metadata_directory_count)
Write-Host ("Selected artifact groups found: {0}" -f $report.filesystem.selected_artifact_group_count)
Write-Host ("Top-level BAT files read: {0}" -f $report.launchers.top_level_bat_count)
Write-Host ("Relevant launcher lines: {0}" -f $report.launchers.relevant_line_count)
Write-Host ("Warnings: {0}" -f $warningCount)
Write-Host ("Normalized report: {0}" -f $reportPath)
Write-Host ("Source report: {0}" -f $sourceReport.FullName)
Write-Host ''
Write-Host 'TensorFlow, DeepFaceLab main.py, and bundled BAT files were not executed.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = 'passed'
    normal_probe_timed_out = [bool]$normal.timed_out
    no_site_probe_timed_out = [bool]$noSite.timed_out
    normal_exit_code = [int]$normal.exit_code
    no_site_exit_code = [int]$noSite.exit_code
    selected_artifact_group_count = [int]$report.filesystem.selected_artifact_group_count
    top_level_bat_count = [int]$report.launchers.top_level_bat_count
    warning_count = $warningCount
}

exit 0
