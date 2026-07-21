[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [switch]$ExtractConfirmed,
    [ValidateRange(60, 1800)][int]$TimeoutSecondsPerRole = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRunner = Join-Path $PSScriptRoot 'run-p0-controlled-face-extraction-v3.ps1'
if (-not (Test-Path -LiteralPath $sourceRunner -PathType Leaf)) {
    throw "Step 13 source runner was not found: $sourceRunner"
}

$oldRootBlock = @'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$validatorScript = Join-Path $PSScriptRoot 'validate-p0-aligned-faces.py'
'@

$newRootTemplate = @'
$step13SourceRoot = '__STEP13_SOURCE_ROOT__'
$repoRoot = (Resolve-Path (Join-Path $step13SourceRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$validatorScript = Join-Path $step13SourceRoot 'validate-p0-aligned-faces.py'
'@

$oldSnapshotBlock = @'
        $relative = $item.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
        $kind = 'F'
        $length = [int64]$item.Length

        if ($item.PSIsContainer) {
            $kind = 'D'
            $length = [int64]0
        }
'@

$newSnapshotBlock = @'
        $relative = $item.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')

        if ($item.PSIsContainer) {
            $kind = 'D'
            $length = [int64]0
        }
        else {
            $kind = 'F'
            $length = [int64]$item.Length
        }
'@

$sourceText = [System.IO.File]::ReadAllText($sourceRunner)
$rootFirstIndex = $sourceText.IndexOf($oldRootBlock, [System.StringComparison]::Ordinal)
$rootLastIndex = $sourceText.LastIndexOf($oldRootBlock, [System.StringComparison]::Ordinal)
$snapshotFirstIndex = $sourceText.IndexOf($oldSnapshotBlock, [System.StringComparison]::Ordinal)
$snapshotLastIndex = $sourceText.LastIndexOf($oldSnapshotBlock, [System.StringComparison]::Ordinal)

if (($rootFirstIndex -lt 0) -or ($rootFirstIndex -ne $rootLastIndex)) {
    throw 'The expected step 13 source-path block was not found exactly once. Nothing was executed.'
}

if (($snapshotFirstIndex -lt 0) -or ($snapshotFirstIndex -ne $snapshotLastIndex)) {
    throw 'The expected PowerShell 5.1 snapshot block was not found exactly once. Nothing was executed.'
}

$escapedSourceRoot = $PSScriptRoot.Replace("'", "''")
$newRootBlock = $newRootTemplate.Replace('__STEP13_SOURCE_ROOT__', $escapedSourceRoot)
$patchedText = $sourceText.Replace($oldRootBlock, $newRootBlock)
$patchedText = $patchedText.Replace($oldSnapshotBlock, $newSnapshotBlock)

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DeepFaceLab-Next-Step13-' + [Guid]::NewGuid().ToString('N'))
$tempRunner = Join-Path $tempRoot 'run-p0-controlled-face-extraction-patched.ps1'
$childExitCode = 1

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    [System.IO.File]::WriteAllText($tempRunner, $patchedText, (New-Object System.Text.UTF8Encoding($true)))

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $tempRunner,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -ne 0) {
        $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "The temporary patched runner did not parse cleanly: $details"
    }

    Write-Host 'PowerShell 5.1 snapshot compatibility patch: PASS' -ForegroundColor Green

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $tempRunner,
        '-ProfilePath', $ProfilePath,
        '-WorkspaceRoot', $WorkspaceRoot,
        '-TimeoutSecondsPerRole', [string]$TimeoutSecondsPerRole
    )

    if ($ExtractConfirmed) {
        $arguments += '-ExtractConfirmed'
    }

    & powershell.exe @arguments
    $childExitCode = $LASTEXITCODE

    if ($null -eq $childExitCode) {
        $childExitCode = 1
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $childExitCode
