[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)][string]$FusionRoot,
    [switch]$AcceptanceConfirmed,
    [switch]$DfmListedConfirmed,
    [switch]$ImageLoadedConfirmed,
    [switch]$FaceDetectedConfirmed,
    [switch]$InferenceExecutedConfirmed,
    [switch]$PreviewChangedConfirmed,
    [switch]$ApplicationStableConfirmed,
    [switch]$NoBlockingProviderErrorsConfirmed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Get-ProfileValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $profile.ContainsKey($Name)) { throw "Missing profile key: $Name" }
    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Empty profile value: $Name" }
    return $value
}

function Get-PropertyValue {
    param([AllowNull()]$Object, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Normalize-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-FileRecord {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file does not exist: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return [ordered]@{
        path = $item.FullName
        name = $item.Name
        size_bytes = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
    }
}

$confirmations = [ordered]@{
    acceptance_confirmed = $AcceptanceConfirmed.IsPresent
    dfm_listed = $DfmListedConfirmed.IsPresent
    target_image_loaded = $ImageLoadedConfirmed.IsPresent
    target_face_detected = $FaceDetectedConfirmed.IsPresent
    inference_executed = $InferenceExecutedConfirmed.IsPresent
    preview_changed = $PreviewChangedConfirmed.IsPresent
    application_stable = $ApplicationStableConfirmed.IsPresent
    no_blocking_provider_or_tensor_errors = $NoBlockingProviderErrorsConfirmed.IsPresent
}
foreach ($entry in $confirmations.GetEnumerator()) {
    if (-not [bool]$entry.Value) {
        throw ("Required VisoMaster acceptance confirmation is missing: {0}" -f $entry.Key)
    }
}

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$workspaceResolved = Normalize-FullPath -Path (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$fusionResolved = Normalize-FullPath -Path (Resolve-Path -LiteralPath $FusionRoot).Path

$exportManifestPath = Join-Path $workspaceResolved 'p0-dfm-export-manifest.json'
$acceptanceMarkerPath = Join-Path $workspaceResolved 'p0-visomaster-fusion-manifest.json'
$fusionMainPy = Join-Path $fusionResolved 'main.py'
$fusionGitDirectory = Join-Path $fusionResolved '.git'

if (-not (Test-Path -LiteralPath $exportManifestPath -PathType Leaf)) {
    throw 'The passed step-17 DFM export manifest is missing.'
}
if (Test-Path -LiteralPath $acceptanceMarkerPath) {
    throw 'A P0 VisoMaster Fusion acceptance marker already exists. Nothing was changed.'
}
if (-not (Test-Path -LiteralPath $fusionMainPy -PathType Leaf)) {
    throw "VisoMaster Fusion main.py was not found: $fusionMainPy"
}
if (-not (Test-Path -LiteralPath $fusionGitDirectory -PathType Container)) {
    throw "VisoMaster Fusion Git metadata was not found: $fusionGitDirectory"
}

$exportManifest = Get-Content -LiteralPath $exportManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string](Get-PropertyValue -Object $exportManifest -Name 'status' -Default '') -ne 'passed') {
    throw 'The step-17 DFM export manifest is not passed.'
}

$sourceDfmPathValue = [string](Get-PropertyValue -Object $exportManifest -Name 'dfm_path' -Default '')
$expectedDfmSize = [int64](Get-PropertyValue -Object $exportManifest -Name 'dfm_size_bytes' -Default -1)
$expectedDfmHash = ([string](Get-PropertyValue -Object $exportManifest -Name 'dfm_sha256' -Default '')).ToUpperInvariant()
$modelPrefix = [string](Get-PropertyValue -Object $exportManifest -Name 'model_prefix' -Default '')
$modelIteration = [int](Get-PropertyValue -Object $exportManifest -Name 'model_iteration' -Default -1)
$onnxCheckerPassed = [bool](Get-PropertyValue -Object $exportManifest -Name 'onnx_checker_passed' -Default $false)
$visualReviewConfirmed = [bool](Get-PropertyValue -Object $exportManifest -Name 'visual_review_confirmed' -Default $false)

if ([string]::IsNullOrWhiteSpace($sourceDfmPathValue) -or [string]::IsNullOrWhiteSpace($expectedDfmHash)) {
    throw 'The step-17 manifest does not contain a usable DFM path and SHA-256.'
}
if ($expectedDfmSize -le 0) { throw 'The step-17 manifest contains an invalid DFM size.' }
if ($modelPrefix -ne 'p0gate_SAEHD' -or $modelIteration -ne 4) {
    throw 'The step-17 manifest model identity or iteration does not match the accepted P0 boundary.'
}
if (-not $onnxCheckerPassed) { throw 'The step-17 manifest does not confirm ONNX checker acceptance.' }
if (-not $visualReviewConfirmed) { throw 'The step-17 manifest does not confirm merge visual review.' }

$sourceDfmPath = Normalize-FullPath -Path $sourceDfmPathValue
$sourceDfm = Get-FileRecord -Path $sourceDfmPath
if ([int64]$sourceDfm.size_bytes -ne $expectedDfmSize) {
    throw 'The workspace DFM size no longer matches the passed export manifest.'
}
if ([string]$sourceDfm.sha256 -ne $expectedDfmHash) {
    throw 'The workspace DFM SHA-256 no longer matches the passed export manifest.'
}

$fusionDfmDirectory = Join-Path $fusionResolved 'model_assets\dfm_models'
$fusionDfmPath = Join-Path $fusionDfmDirectory ([string]$sourceDfm.name)
$fusionDfm = Get-FileRecord -Path $fusionDfmPath
if ([int64]$fusionDfm.size_bytes -ne [int64]$sourceDfm.size_bytes) {
    throw 'The VisoMaster Fusion DFM copy size does not match the exported workspace DFM.'
}
if ([string]$fusionDfm.sha256 -ne [string]$sourceDfm.sha256) {
    throw 'The VisoMaster Fusion DFM copy SHA-256 does not match the exported workspace DFM.'
}

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) {
    throw 'The DeepFaceLab-Next Git working tree is not clean.'
}

$fusionCommit = (& git -C $fusionResolved rev-parse HEAD 2>$null | Out-String).Trim()
$fusionBranch = (& git -C $fusionResolved rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($fusionCommit)) { throw 'Unable to read the VisoMaster Fusion Git commit.' }

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$artifactRoot = Join-Path $repoRoot ("artifacts\p0\{0}\{1}" -f $machineId, $environmentId)
$outputDirectory = Join-Path $artifactRoot 'visomaster-fusion'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("p0-visomaster-fusion-acceptance-v2-{0}.json" -f $fileTimestamp)

$repoStatusAfter = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
$repoUnchanged = $repoStatusBefore -eq $repoStatusAfter
if (-not $repoUnchanged) { throw 'The DeepFaceLab-Next Git working tree changed during acceptance recording.' }

$report = [ordered]@{
    schema_version = 2
    status = 'passed'
    recorded_at_utc = $timestamp.ToString('o')
    report_path = $reportPath
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    workspace_root = $workspaceResolved
    source_export_manifest = $exportManifestPath
    model_prefix = $modelPrefix
    model_iteration = $modelIteration
    dfm = $sourceDfm
    visomaster = [ordered]@{
        root = $fusionResolved
        git_branch = $fusionBranch
        git_commit = $fusionCommit
        main_py = $fusionMainPy
        installed_dfm = $fusionDfm
    }
    operator_acceptance = $confirmations
    observed_test_boundary = [ordered]@{
        target_media_type = 'authorized synthetic still image'
        source_face_card_required_for_dfm = $false
        swapper_model = 'DeepFaceLive (DFM)'
        amp_morph_factor = 50
        rct_color_transfer = $false
        quality_claimed = $false
        purpose = 'compatibility and reproducibility only'
    }
    integrity = [ordered]@{
        workspace_and_fusion_dfm_match = $true
        exported_dfm_matches_step17_manifest = $true
        onnx_checker_passed = $onnxCheckerPassed
        merge_visual_review_confirmed = $visualReviewConfirmed
        repository_unchanged = $repoUnchanged
        private_media_committed = $false
        checkpoint_or_dfm_committed = $false
    }
    decision = 'P0 Gate F accepted: the validated DFM was listed, loaded, and executed in VisoMaster Fusion without a blocking provider, tensor, or application-stability failure.'
}
[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 12), $utf8Bom)

$marker = [ordered]@{
    schema_version = 2
    status = 'passed'
    recorded_at_utc = $report.recorded_at_utc
    report_path = $reportPath
    machine_id = $machineId
    environment_id = $environmentId
    model_prefix = $modelPrefix
    model_iteration = $modelIteration
    dfm_name = [string]$sourceDfm.name
    dfm_size_bytes = [int64]$sourceDfm.size_bytes
    dfm_sha256 = [string]$sourceDfm.sha256
    visomaster_git_branch = $fusionBranch
    visomaster_git_commit = $fusionCommit
    dfm_listed = $true
    target_image_loaded = $true
    target_face_detected = $true
    inference_executed = $true
    preview_changed = $true
    application_stable = $true
    no_blocking_provider_or_tensor_errors = $true
    quality_claimed = $false
}

$markerTempPath = $acceptanceMarkerPath + '.partial-' + [Guid]::NewGuid().ToString('N')
try {
    [System.IO.File]::WriteAllText($markerTempPath, ($marker | ConvertTo-Json -Depth 8), $utf8Bom)
    Move-Item -LiteralPath $markerTempPath -Destination $acceptanceMarkerPath -ErrorAction Stop
}
finally {
    if (Test-Path -LiteralPath $markerTempPath) {
        Remove-Item -LiteralPath $markerTempPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host 'P0 VisoMaster Fusion acceptance record v2' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $report.status)
Write-Host ("Model: {0}; iteration: {1}" -f $modelPrefix, $modelIteration)
Write-Host ("DFM: {0}; bytes: {1}" -f $sourceDfm.name, $sourceDfm.size_bytes)
Write-Host ("DFM SHA-256: {0}" -f $sourceDfm.sha256)
Write-Host ("VisoMaster: branch {0}; commit {1}" -f $fusionBranch, $fusionCommit)
Write-Host ("DFM listed: {0}; inference executed: {1}; preview changed: {2}" -f $confirmations.dfm_listed, $confirmations.inference_executed, $confirmations.preview_changed)
Write-Host ("Application stable: {0}; no blocking provider/tensor errors: {1}" -f $confirmations.application_stable, $confirmations.no_blocking_provider_or_tensor_errors)
Write-Host ("Repository unchanged: {0}" -f $repoUnchanged)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ("Workspace marker: {0}" -f $acceptanceMarkerPath)
Write-Host ''
Write-Host 'Safety boundary' -ForegroundColor Yellow
Write-Host 'This step only recorded the already-observed compatibility result. It did not train, merge, export, or run VisoMaster Fusion.'

[PSCustomObject]@{
    report_path = $reportPath
    marker_path = $acceptanceMarkerPath
    status = $report.status
    model_prefix = $modelPrefix
    model_iteration = $modelIteration
    dfm_size_bytes = [int64]$sourceDfm.size_bytes
    dfm_sha256 = [string]$sourceDfm.sha256
    visomaster_branch = $fusionBranch
    visomaster_commit = $fusionCommit
    dfm_listed = $true
    inference_executed = $true
    preview_changed = $true
    application_stable = $true
    no_blocking_provider_or_tensor_errors = $true
    repository_unchanged = $repoUnchanged
}
