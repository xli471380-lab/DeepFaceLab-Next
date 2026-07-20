[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [ValidateRange(30, 1800)][int]$TimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$targetScript = Join-Path $PSScriptRoot 'inspect-legacy-python-layout.ps1'
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path

if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) {
    throw "Inspection script was not found: $targetScript"
}

$tempRoot = Join-Path $env:TEMP ("dflnext-python-layout-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$stdoutPath = Join-Path $tempRoot 'stdout.txt'
$stderrPath = Join-Path $tempRoot 'stderr.txt'

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
}

$process = $null
$completed = $false
try {
    Write-Host ''
    Write-Host '[1/4] Starting the isolated read-only diagnostics process...' -ForegroundColor Cyan
    Write-Host ("Profile: {0}" -f $profileResolved)
    Write-Host ("Timeout: {0} seconds" -f $TimeoutSeconds)
    Write-Host ''
    Write-Host '[2/4] Checking embedded Python sys.path and site-packages...' -ForegroundColor Cyan
    Write-Host 'Progress will be printed every 10 seconds. TensorFlow is not imported.'
    Write-Host ''

    $argumentString = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ProfilePath "{1}"' -f `
        $targetScript.Replace('"', '\"'),
        $profileResolved.Replace('"', '\"')

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

        if ($elapsedSeconds -ge $nextProgressSeconds) {
            Write-Host ("Still running safely... elapsed {0}s / timeout {1}s" -f $elapsedSeconds, $TimeoutSeconds) -ForegroundColor DarkCyan
            $nextProgressSeconds += 10
        }

        if ($elapsedSeconds -ge $TimeoutSeconds) {
            Write-Host ''
            Write-Host ("Timeout reached after {0} seconds. Stopping the read-only process tree." -f $TimeoutSeconds) -ForegroundColor Yellow
            Stop-ProcessTree -ProcessId $process.Id
            throw "Legacy Python layout diagnostics timed out after $TimeoutSeconds seconds."
        }
    }

    $completed = $true
    $exitCode = $process.ExitCode

    Write-Host ''
    Write-Host '[3/4] Diagnostics process finished. Reading captured output...' -ForegroundColor Cyan
    Write-Host ''

    if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-Host $stdout.TrimEnd()
        }
    }

    if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Host ''
            Write-Host 'Captured error output:' -ForegroundColor Yellow
            Write-Host $stderr.TrimEnd() -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host '[4/4] Wrapper completed.' -ForegroundColor Cyan

    if ($exitCode -ne 0) {
        exit $exitCode
    }

    exit 0
}
finally {
    if ($null -ne $process -and -not $completed) {
        try {
            $process.Refresh()
            if (-not $process.HasExited) {
                Stop-ProcessTree -ProcessId $process.Id
            }
        }
        catch {
        }
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
