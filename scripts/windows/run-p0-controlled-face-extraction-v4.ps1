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

$oldBlock = @'
        $relative = $item.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
        $kind = 'F'
        $length = [int64]$item.Length

        if ($item.PSIsContainer) {
            $kind = 'D'
            $length = [int64]0
        }
'@

$newBlock = @'
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
$firstIndex = $sourceText.IndexOf($oldBlock, [System.StringComparison]::Ordinal)
$lastIndex = $sourceText.LastIndexOf($oldBlock, [System.StringComparison]::Ordinal)

if ($firstIndex -lt 0) {
    throw 'The expected PowerShell 5.1 snapshot block was not found. Nothing was executed.'
}

if ($firstIndex -ne $lastIndex) {
    throw 'The expected snapshot block occurred more than once. Nothing was executed.'
}

$patchedText = $sourceText.Substring(0, $firstIndex) + $newBlock + $sourceText.Substring($firstIndex + $oldBlock.Length)
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
