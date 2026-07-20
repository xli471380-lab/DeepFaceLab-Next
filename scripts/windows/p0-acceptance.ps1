[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$PythonExe,
    [switch]$AllowDirtyTree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'artifacts\p0'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$checks = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Details,
        [bool]$Required = $true
    )

    $record = [PSCustomObject]@{
        name = $Name
        passed = $Passed
        required = $Required
        details = $Details
    }
    $checks.Add($record)

    if ($Required -and -not $Passed) {
        $failures.Add($record)
    }
    elseif (-not $Required -and -not $Passed) {
        $warnings.Add(("{0}: {1}" -f $Name, $Details))
    }
}

function Invoke-NativeText {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        return [PSCustomObject]@{
            exit_code = $LASTEXITCODE
            output = ($lines -join [Environment]::NewLine).Trim()
        }
    }
    catch {
        return [PSCustomObject]@{
            exit_code = -1
            output = $_.Exception.ToString()
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Invoke-Git {
    param([string[]]$Arguments)

    $captured = Invoke-NativeText -Executable 'git' -Arguments (@('-C', $repoRoot) + $Arguments)
    if ($captured.exit_code -ne 0) {
        throw ("git {0} failed: {1}" -f ($Arguments -join ' '), $captured.output)
    }
    return $captured.output
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
Add-Check -Name 'git_available' -Passed ($null -ne $gitCommand) -Details $(
    if ($null -ne $gitCommand) { $gitCommand.Source } else { 'Git was not found on PATH.' }
)

$commit = $null
$branch = $null
$statusPorcelain = $null
$origin = $null
if ($null -ne $gitCommand) {
    $commit = Invoke-Git -Arguments @('rev-parse', 'HEAD')
    $branch = Invoke-Git -Arguments @('branch', '--show-current')
    $statusPorcelain = Invoke-Git -Arguments @('status', '--porcelain')
    $origin = Invoke-Git -Arguments @('remote', 'get-url', 'origin')

    Add-Check -Name 'repository_origin' -Passed ($origin -match 'xli471380-lab/DeepFaceLab-Next(?:\.git)?$') -Details $origin
    Add-Check -Name 'commit_recorded' -Passed (-not [string]::IsNullOrWhiteSpace($commit)) -Details $commit
    Add-Check -Name 'branch_recorded' -Passed (-not [string]::IsNullOrWhiteSpace($branch)) -Details $branch

    $cleanTree = [string]::IsNullOrWhiteSpace($statusPorcelain)
    Add-Check -Name 'working_tree_clean' -Passed ($cleanTree -or $AllowDirtyTree.IsPresent) -Details $(
        if ($cleanTree) { 'Working tree is clean.' }
        elseif ($AllowDirtyTree.IsPresent) { 'Working tree is dirty but -AllowDirtyTree was supplied.' }
        else { $statusPorcelain }
    )
}

$requiredPaths = @(
    'LICENSE',
    'main.py',
    'core',
    'facelib',
    'models',
    'samplelib',
    'merger',
    'requirements-cuda.txt'
)
foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $repoRoot $relativePath
    Add-Check -Name ("path_{0}" -f ($relativePath -replace '[^A-Za-z0-9]+', '_')) -Passed (Test-Path -LiteralPath $fullPath) -Details $relativePath
}

$trackedSensitive = @()
if ($null -ne $gitCommand) {
    $trackedFiles = Invoke-Git -Arguments @('ls-files')
    if (-not [string]::IsNullOrWhiteSpace($trackedFiles)) {
        # Force an array even when the filter returns zero or one item.
        $trackedSensitive = @(
            $trackedFiles -split "`r?`n" | Where-Object {
                $_ -match '^(workspace|artifacts)/' -or $_ -match '\.dfm$'
            }
        )
    }
}
$trackedSensitiveCount = @($trackedSensitive).Count
Add-Check -Name 'no_tracked_private_artifacts' -Passed ($trackedSensitiveCount -eq 0) -Details $(
    if ($trackedSensitiveCount -eq 0) { 'No workspace, artifacts, or DFM files are tracked.' }
    else { @($trackedSensitive) -join '; ' }
)

$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
Add-Check -Name 'nvidia_smi_available' -Passed ($null -ne $nvidiaSmi) -Details $(
    if ($null -ne $nvidiaSmi) { $nvidiaSmi.Source } else { 'nvidia-smi was not found on PATH.' }
)

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
Add-Check -Name 'ffmpeg_available' -Passed ($null -ne $ffmpeg) -Details $(
    if ($null -ne $ffmpeg) { $ffmpeg.Source }
    else { 'FFmpeg was not found on PATH. A bundled executable may be supplied later.' }
) -Required $false

$pythonCheckPassed = $false
$pythonDetails = 'No Python executable was supplied and python was not found on PATH.'
$resolvedPython = $null
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
    if (Test-Path -LiteralPath $PythonExe -PathType Leaf) {
        $resolvedPython = (Resolve-Path -LiteralPath $PythonExe).Path
    }
    else {
        $pythonDetails = ("Python executable does not exist: {0}" -f $PythonExe)
    }
}
else {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) {
        $resolvedPython = $pythonCommand.Source
    }
}

if (-not [string]::IsNullOrWhiteSpace($resolvedPython)) {
    $pythonProbe = Invoke-NativeText -Executable $resolvedPython -Arguments @(
        '-c',
        'import sys; print(sys.executable); print(sys.version.replace(chr(10), " "))'
    )
    $pythonCheckPassed = ($pythonProbe.exit_code -eq 0)
    $pythonDetails = $pythonProbe.output
}
Add-Check -Name 'python_runtime_visible' -Passed $pythonCheckPassed -Details $pythonDetails -Required $false

$diagnosticScript = Join-Path $PSScriptRoot 'system-diagnostics.ps1'
$diagnosticParameters = @{
    OutputDirectory = $OutputDirectory
}
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
    $diagnosticParameters['PythonExe'] = $PythonExe
}

$diagnosticObjects = @(& $diagnosticScript @diagnosticParameters)
$diagnosticResult = @($diagnosticObjects | Where-Object {
    $_ -is [PSObject] -and $_.PSObject.Properties.Name -contains 'report_path'
} | Select-Object -Last 1)

$diagnosticReportPath = $null
if ($diagnosticResult.Count -gt 0) {
    $diagnosticReportPath = $diagnosticResult[0].report_path
}
Add-Check -Name 'diagnostics_report_written' -Passed (
    -not [string]::IsNullOrWhiteSpace($diagnosticReportPath) -and
    (Test-Path -LiteralPath $diagnosticReportPath -PathType Leaf)
) -Details $(
    if ([string]::IsNullOrWhiteSpace($diagnosticReportPath)) {
        'The diagnostics script did not return a report path.'
    }
    else {
        $diagnosticReportPath
    }
)

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$summaryPath = Join-Path $OutputDirectory ("acceptance-summary-{0}.json" -f $fileTimestamp)

$summary = [ordered]@{
    schema_version = 2
    generated_at_utc = $timestamp.ToString('o')
    phase = 'p0_environment_scaffold'
    status = $(if ($failures.Count -eq 0) { 'passed' } else { 'blocked' })
    repository = [ordered]@{
        root = $repoRoot
        origin = $origin
        branch = $branch
        commit = $commit
    }
    diagnostics_report = $diagnosticReportPath
    checks = @($checks)
    failures = @($failures)
    warnings = @($warnings)
    next_required_gates = @(
        'authorized_face_extraction',
        'short_training_run',
        'checkpoint_save_and_resume',
        'merge_test_clip',
        'dfm_export',
        'visomaster_fusion_load'
    )
    note = 'This scaffold validates repository and machine readiness only. It does not by itself complete P0.'
}

$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host 'P0 environment scaffold passed.' -ForegroundColor Green
}
else {
    Write-Host 'P0 environment scaffold is blocked.' -ForegroundColor Red
}
Write-Host ("Summary: {0}" -f $summaryPath)
Write-Host ("Diagnostics: {0}" -f $diagnosticReportPath)

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Required failures:' -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host ("- {0}: {1}" -f $failure.name, $failure.details) -ForegroundColor Red
    }
    exit 1
}

exit 0
