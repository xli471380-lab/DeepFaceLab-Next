[CmdletBinding()]
param(
    [string]$PythonExe = '',
    [string]$RepoRoot = '',
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    }
    if ($null -eq $pythonCommand) {
        throw 'Python 3 was not found. Pass -PythonExe with an explicit system Python path.'
    }
    $PythonExe = $pythonCommand.Source
}
elseif (Test-Path -LiteralPath $PythonExe -PathType Leaf) {
    $PythonExe = (Resolve-Path -LiteralPath $PythonExe).Path
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot '.p1-local\repository-privacy-report.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot $OutputPath
}

$validator = Join-Path $RepoRoot 'scripts\p1\repository_privacy_validator.py'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "P1 repository privacy validator was not found: $validator"
}

Write-Host ''
Write-Host 'P1 repository privacy and boundary gate' -ForegroundColor Cyan
Write-Host ("Repository: {0}" -f $RepoRoot)
Write-Host ("Python: {0}" -f $PythonExe)
Write-Host ("Report: {0}" -f $OutputPath)
Write-Host ''
Write-Host 'Safety boundary' -ForegroundColor Yellow
Write-Host '- CPU-only; no GPU or historical runtime required'
Write-Host '- does not read media, checkpoint, DFM, or embedding contents'
Write-Host '- does not modify tracked repository files'
Write-Host '- writes only the ignored .p1-local report'
Write-Host ''

& $PythonExe `
    $validator `
    '--repo-root' $RepoRoot `
    '--json-output' $OutputPath

$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 4 }

Write-Host ''
if ($exitCode -eq 0) {
    Write-Host 'P1 repository privacy gate passed.' -ForegroundColor Green
}
elseif ($exitCode -eq 2) {
    Write-Host 'P1 repository privacy gate blocked because prohibited tracked paths or file types were found.' -ForegroundColor Red
}
else {
    Write-Host ("P1 repository privacy gate could not complete. Exit code: {0}" -f $exitCode) -ForegroundColor Red
}

exit $exitCode
