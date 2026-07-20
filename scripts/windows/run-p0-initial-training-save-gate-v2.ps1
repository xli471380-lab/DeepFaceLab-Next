[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [switch]$VisualReviewConfirmed,
    [ValidateRange(300, 1800)][int]$TimeoutSeconds = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRunner = Join-Path $PSScriptRoot 'run-p0-initial-training-save-gate.ps1'
$scriptedInputRunner = Join-Path $PSScriptRoot 'run-p0-dfl-with-scripted-input.py'

foreach ($requiredFile in @($sourceRunner, $scriptedInputRunner)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Step 14 compatibility input is missing: $requiredFile"
    }
}

$oldRootBlock = @'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$validatorScript = Join-Path $PSScriptRoot 'validate-p0-training-checkpoint.py'
'@

$newRootTemplate = @'
$step14SourceRoot = '__STEP14_SOURCE_ROOT__'
$repoRoot = (Resolve-Path (Join-Path $step14SourceRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$validatorScript = Join-Path $step14SourceRoot 'validate-p0-training-checkpoint.py'
$scriptedInputRunner = Join-Path $step14SourceRoot 'run-p0-dfl-with-scripted-input.py'
'@

$oldTrainingBlock = @'
$trainingArguments = @(
    $mainPy,
    'train',
    '--training-data-src-dir', $sourceAligned,
    '--training-data-dst-dir', $destinationAligned,
    '--model-dir', $stagingModelDirectory,
    '--model', $modelClass,
    '--no-preview',
    '--force-model-name', $modelBaseName,
    '--force-gpu-idxs', '0',
    '--execute-program', '-1', $closeProgram
)
'@

$newTrainingBlock = @'
$promptAnswersJson = $promptAnswers | ConvertTo-Json -Compress
$promptAnswersBase64 = [System.Convert]::ToBase64String(
    [System.Text.Encoding]::UTF8.GetBytes($promptAnswersJson)
)
$trainingArguments = @(
    $scriptedInputRunner,
    '--dfl-root', $deepFaceLabRoot,
    '--main-py', $mainPy,
    '--answers-b64', $promptAnswersBase64,
    '--',
    'train',
    '--training-data-src-dir', $sourceAligned,
    '--training-data-dst-dir', $destinationAligned,
    '--model-dir', $stagingModelDirectory,
    '--model', $modelClass,
    '--no-preview',
    '--force-model-name', $modelBaseName,
    '--force-gpu-idxs', '0',
    '--execute-program', '-1', $closeProgram
)
'@

$oldInvokeLine = @'
    $trainingProcess = Invoke-IsolatedPython -Label 'initial-training' -Arguments $trainingArguments -ProcessTimeoutSeconds $TimeoutSeconds -InputLines $promptAnswers
'@

$newInvokeLine = @'
    $trainingProcess = Invoke-IsolatedPython -Label 'initial-training' -Arguments $trainingArguments -ProcessTimeoutSeconds $TimeoutSeconds
'@

$oldIsolationLine = @'
        partial_staging_removed_on_block = $true
'@

$newIsolationLine = @'
        partial_staging_removed_on_block = $true
        scripted_prompt_driver = $scriptedInputRunner
        scripted_answer_count = @($promptAnswers).Count
'@

$oldBoundedLine = @'
        training_bounded_to_target_iteration = $true
'@

$newBoundedLine = @'
        training_bounded_to_target_iteration = ($status -eq 'passed' -and [int]$iteration -eq $targetIteration)
'@

$oldSafetyOutput = @'
Write-Host '[4/4] Safety boundary' -ForegroundColor Cyan
Write-Host 'Only a two-iteration SAEHD checkpoint was created and saved. Resume, merge, and DFM export were not started.' -ForegroundColor Yellow
'@

$newSafetyOutput = @'
Write-Host '[4/4] Safety boundary' -ForegroundColor Cyan
if ($status -eq 'passed') {
    Write-Host 'A validated two-iteration SAEHD checkpoint was created and saved. Resume, merge, and DFM export were not started.' -ForegroundColor Yellow
}
else {
    Write-Host 'The generated temporary checkpoint was blocked and removed. No persistent model was committed; resume, merge, and DFM export were not started.' -ForegroundColor Yellow
}
'@

$sourceText = [System.IO.File]::ReadAllText($sourceRunner)

$replacementPairs = @(
    [ordered]@{ Name = 'source path block'; Old = $oldRootBlock; New = $newRootTemplate },
    [ordered]@{ Name = 'training argument block'; Old = $oldTrainingBlock; New = $newTrainingBlock },
    [ordered]@{ Name = 'training invocation'; Old = $oldInvokeLine; New = $newInvokeLine },
    [ordered]@{ Name = 'isolation report block'; Old = $oldIsolationLine; New = $newIsolationLine },
    [ordered]@{ Name = 'bounded-training report field'; Old = $oldBoundedLine; New = $newBoundedLine },
    [ordered]@{ Name = 'safety terminal output'; Old = $oldSafetyOutput; New = $newSafetyOutput }
)

foreach ($pair in $replacementPairs) {
    $firstIndex = $sourceText.IndexOf($pair.Old, [System.StringComparison]::Ordinal)
    $lastIndex = $sourceText.LastIndexOf($pair.Old, [System.StringComparison]::Ordinal)
    if (($firstIndex -lt 0) -or ($firstIndex -ne $lastIndex)) {
        throw ("The expected {0} was not found exactly once. Nothing was executed." -f $pair.Name)
    }
}

$escapedSourceRoot = $PSScriptRoot.Replace("'", "''")
$newRootBlock = $newRootTemplate.Replace('__STEP14_SOURCE_ROOT__', $escapedSourceRoot)
$patchedText = $sourceText.Replace($oldRootBlock, $newRootBlock)
$patchedText = $patchedText.Replace($oldTrainingBlock, $newTrainingBlock)
$patchedText = $patchedText.Replace($oldInvokeLine, $newInvokeLine)
$patchedText = $patchedText.Replace($oldIsolationLine, $newIsolationLine)
$patchedText = $patchedText.Replace($oldBoundedLine, $newBoundedLine)
$patchedText = $patchedText.Replace($oldSafetyOutput, $newSafetyOutput)

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DeepFaceLab-Next-Step14-' + [Guid]::NewGuid().ToString('N'))
$tempRunner = Join-Path $tempRoot 'run-p0-initial-training-save-gate-patched.ps1'
$childExitCode = 1

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $tempRunner,
        $patchedText,
        (New-Object System.Text.UTF8Encoding($true))
    )

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $tempRunner,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -ne 0) {
        $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "The temporary step 14 runner did not parse cleanly: $details"
    }

    Write-Host 'Step 14 deterministic scripted-input compatibility patch: PASS' -ForegroundColor Green

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $tempRunner,
        '-ProfilePath', $ProfilePath,
        '-WorkspaceRoot', $WorkspaceRoot,
        '-TimeoutSeconds', [string]$TimeoutSeconds
    )

    if ($VisualReviewConfirmed) {
        $arguments += '-VisualReviewConfirmed'
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
