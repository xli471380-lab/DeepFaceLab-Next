[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [ValidateRange(60, 1800)][int]$TimeoutSeconds = 180,
    [ValidateRange(5, 300)][int]$PythonProbeTimeoutSeconds = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$targetScript = Join-Path $PSScriptRoot 'inspect-legacy-python-layout-v4.ps1'
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path

if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) {
    throw "Inspection script was not found: $targetScript"
}

$tempRoot = Join-Path $env:TEMP ("dflnext-python-layout-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$stdoutPath = Join-Path $tempRoot 'stdout.txt'
$stderrPath = Join-Path $tempRoot 'stderr.txt'
$progressPath = Join-Path $tempRoot 'progress.json'

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
}

function Read-ProgressRecord {
    if (-not (Test-Path -LiteralPath $progressPath -PathType Leaf)) { return $null }

    try {
        return Get-Content -LiteralPath $progressPath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

$process = $null
$completed = $false
$lastStage = $null
$lastMessage = $null
try {
    Write-Host ''
    Write-Host '[1/4] Starting compact staged read-only diagnostics...' -ForegroundColor Cyan
    Write-Host ("Profile: {0}" -f $profileResolved)
    Write-Host ("Overall timeout: {0} seconds" -f $TimeoutSeconds)
    Write-Host ("Per Python probe timeout: {0} seconds" -f $PythonProbeTimeoutSeconds)
    Write-Host ''
    Write-Host '[2/4] Running isolated stages. TensorFlow is not imported.' -ForegroundColor Cyan
    Write-Host 'Large inventories are written as text files; the main JSON remains compact.'
    Write-Host 'Windows PowerShell 5.1 missing native exit codes are normalized only after strict evidence checks.'
    Write-Host ''

    $argumentString = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ProfilePath "{1}" -ProgressPath "{2}" -PythonProbeTimeoutSeconds {3}' -f `
        $targetScript.Replace('"', '\"'),
        $profileResolved.Replace('"', '\"'),
        $progressPath.Replace('"', '\"'),
        $PythonProbeTimeoutSeconds

    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList $argumentString `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    $startedAt = Get-Date
    $nextProgressSeconds = 10

    while (-not $process.HasExited) {
        Start-Sleep -Seconds 1
        $process.Refresh()
        $elapsedSeconds = [int]((Get-Date) - $startedAt).TotalSeconds

        $progress = Read-ProgressRecord
        if ($null -ne $progress) {
            $stage = [string]$progress.stage
            $message = [string]$progress.message
            if ($stage -ne $lastStage -or $message -ne $lastMessage) {
                Write-Host ("Stage: {0}" -f $stage) -ForegroundColor Cyan
                Write-Host ("  {0}" -f $message)
                $lastStage = $stage
                $lastMessage = $message
            }
        }

        if ($elapsedSeconds -ge $nextProgressSeconds) {
            $stageText = if ([string]::IsNullOrWhiteSpace($lastStage)) { 'starting' } else { $lastStage }
            Write-Host ("Still running safely... elapsed {0}s / timeout {1}s / stage {2}" -f $elapsedSeconds, $TimeoutSeconds, $stageText) -ForegroundColor DarkCyan
            $nextProgressSeconds += 10
        }

        if ($elapsedSeconds -ge $TimeoutSeconds) {
            Write-Host ''
            Write-Host ("Overall timeout reached after {0} seconds at stage '{1}'." -f $TimeoutSeconds, $lastStage) -ForegroundColor Yellow
            Write-Host 'Stopping the read-only process tree.' -ForegroundColor Yellow
            Stop-ProcessTree -ProcessId $process.Id
            throw "Legacy Python layout diagnostics timed out at stage '$lastStage' after $TimeoutSeconds seconds."
        }
    }

    $completed = $true
    $process.WaitForExit()
    $process.Refresh()
    $exitCode = $process.ExitCode
    $stdout = ''
    $stderr = ''

    Write-Host ''
    Write-Host '[3/4] Staged diagnostics finished. Reading captured output...' -ForegroundColor Cyan
    Write-Host ''

    if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
        $stdout = [string](Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue)
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-Host $stdout.TrimEnd()
        }
    }

    if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
        $stderr = [string](Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Host ''
            Write-Host 'Captured error output:' -ForegroundColor Yellow
            Write-Host $stderr.TrimEnd() -ForegroundColor Yellow
        }
    }

    if ($null -eq $exitCode) {
        if ($stdout -match '(?m)^Status:\s*passed\s*$') {
            $exitCode = 0
            Write-Host ''
            Write-Host 'Outer process exit code was unavailable; explicit passed status was used.' -ForegroundColor DarkYellow
        }
        else {
            $exitCode = 1
            Write-Host ''
            Write-Host 'Outer process exit code was unavailable and no explicit passed status was found.' -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host '[4/4] Wrapper completed.' -ForegroundColor Cyan

    if ([int]$exitCode -ne 0) { exit [int]$exitCode }
    exit 0
}
finally {
    if ($null -ne $process -and -not $completed) {
        try {
            $process.Refresh()
            if (-not $process.HasExited) { Stop-ProcessTree -ProcessId $process.Id }
        }
        catch {
        }
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
