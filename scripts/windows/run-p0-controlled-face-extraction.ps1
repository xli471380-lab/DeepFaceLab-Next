[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [switch]$ExtractConfirmed,
    [ValidateRange(60, 1800)][int]$TimeoutSecondsPerRole = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'run-p0-controlled-face-extraction-v3.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "Step 13 PowerShell 5.1 runner was not found: $runner"
}

& $runner @PSBoundParameters
$runnerExitCode = $LASTEXITCODE

if ($null -eq $runnerExitCode) {
    $runnerExitCode = 1
}

exit $runnerExitCode
