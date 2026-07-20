[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [string]$DatasetManifestPath,
    [switch]$PrepareConfirmed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved

function Get-ProfileValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $profile.ContainsKey($Name)) { throw "Missing profile key: $Name" }
    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Empty profile value: $Name" }
    return $value
}

function Normalize-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $candidateFull = Normalize-FullPath -Path $Candidate
    $parentFull = Normalize-FullPath -Path $Parent

    if ($candidateFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidateFull.StartsWith($parentFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $items = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
    $files = @($items | Where-Object { -not $_.PSIsContainer })
    $directories = @($items | Where-Object { $_.PSIsContainer })
    $builder = New-Object System.Text.StringBuilder

    foreach ($item in $items) {
        $relative = $item.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
        $kind = if ($item.PSIsContainer) { 'D' } else { 'F' }
        $length = if ($item.PSIsContainer) { 0 } else { [int64]$item.Length }
        [void]$builder.Append($kind).Append('|').Append($relative).Append('|').Append($length).Append('|').Append($item.LastWriteTimeUtc.Ticks).Append("`n")
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        $hash = ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }

    $totalBytes = [int64]0
    foreach ($file in $files) { $totalBytes += [int64]$file.Length }

    return [ordered]@{
        path = $Path
        file_count = $files.Count
        directory_count = $directories.Count
        total_bytes = $totalBytes
        metadata_sha256 = $hash
    }
}

function Get-ManifestFiles {
    param(
        [Parameter(Mandatory = $true)]$ManifestRole,
        [Parameter(Mandatory = $true)][string]$Role
    )

    $files = @($ManifestRole.files)
    if ($files.Count -eq 0) { throw "The dataset manifest contains no files for role '$Role'." }

    return $files
}

function Confirm-ManifestFiles {
    param(
        [Parameter(Mandatory = $true)]$Files,
        [Parameter(Mandatory = $true)][string]$Role
    )

    $verified = New-Object System.Collections.ArrayList
    $index = 0

    foreach ($record in @($Files)) {
        $index++
        $sourcePath = [string]$record.full_path
        $expectedHash = [string]$record.sha256

        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Manifest file is missing for role '$Role': $sourcePath"
        }

        Write-Host ("  [{0}] verify {1}/{2}: {3}" -f $Role, $index, @($Files).Count, (Split-Path -Leaf $sourcePath)) -ForegroundColor DarkCyan
        $actualHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actualHash -ne $expectedHash) {
            throw "Manifest hash mismatch for role '$Role': $sourcePath"
        }

        [void]$verified.Add([ordered]@{
            role = $Role
            source_path = $sourcePath
            sha256 = $actualHash
            extension = [System.IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
            size_bytes = [int64](Get-Item -LiteralPath $sourcePath -Force).Length
        })
    }

    return @($verified | ForEach-Object { $_ })
}

if (-not $PrepareConfirmed) {
    throw 'Workspace preparation confirmation was not supplied. Use the step-12 BAT and confirm the bounded copy operation.'
}

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$runtimeRoot = Normalize-FullPath -Path (Get-ProfileValue 'RuntimeRoot')
$defaultWorkspace = Normalize-FullPath -Path (Get-ProfileValue 'WorkspacePath')
$repoRootNormalized = Normalize-FullPath -Path $repoRoot
$workspaceResolved = Normalize-FullPath -Path $WorkspaceRoot

if (Test-Path -LiteralPath $workspaceResolved) {
    throw "The isolated workspace target already exists. Choose a new empty path; nothing will be overwritten: $workspaceResolved"
}
if (Test-PathInside -Candidate $workspaceResolved -Parent $repoRootNormalized) {
    throw "The isolated workspace must stay outside the Git repository: $workspaceResolved"
}
if (Test-PathInside -Candidate $workspaceResolved -Parent $runtimeRoot) {
    throw "The isolated workspace must stay outside the historical runtime: $workspaceResolved"
}

$artifactRoot = Join-Path $repoRoot ("artifacts\p0\{0}\{1}" -f $machineId, $environmentId)
if ([string]::IsNullOrWhiteSpace($DatasetManifestPath)) {
    $manifestDirectory = Join-Path $artifactRoot 'dataset-preflight'
    $manifestFile = Get-ChildItem -LiteralPath $manifestDirectory -Filter 'p0-authorized-dataset-manifest-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $manifestFile) { throw 'No step-11 dataset manifest was found for this profile.' }
    $manifestResolved = $manifestFile.FullName
}
else {
    $manifestResolved = (Resolve-Path -LiteralPath $DatasetManifestPath).Path
}

$manifest = Get-Content -LiteralPath $manifestResolved -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string]$manifest.status -ne 'passed') { throw "The dataset manifest is not passed: $manifestResolved" }
if (-not [bool]$manifest.authorization.confirmed_by_user) { throw 'The dataset manifest does not contain authorization confirmation.' }
if ([System.IO.Path]::GetFullPath([string]$manifest.profile_path) -ne [System.IO.Path]::GetFullPath($profileResolved)) {
    throw 'The dataset manifest belongs to a different local profile.'
}

$sourceRoot = Normalize-FullPath -Path ([string]$manifest.source.root_path)
$destinationRoot = Normalize-FullPath -Path ([string]$manifest.destination.root_path)
foreach ($mediaRoot in @($sourceRoot, $destinationRoot)) {
    if ((Test-PathInside -Candidate $workspaceResolved -Parent $mediaRoot) -or (Test-PathInside -Candidate $mediaRoot -Parent $workspaceResolved)) {
        throw 'The isolated workspace and original media paths must not contain one another.'
    }
}

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) {
    throw 'The repository working tree is not clean. Commit, stash, or remove unrelated changes before preparing the isolated workspace.'
}
$defaultWorkspaceBefore = Get-TreeSnapshot -Path $defaultWorkspace

Write-Host ''
Write-Host '[1/4] Verifying the passed dataset manifest and all source hashes...' -ForegroundColor Cyan
Write-Host ("Profile: {0}" -f $profileResolved)
Write-Host ("Dataset manifest: {0}" -f $manifestResolved)
Write-Host ("Isolated workspace target: {0}" -f $workspaceResolved)
Write-Host ''

$sourceFiles = Get-ManifestFiles -ManifestRole $manifest.source -Role 'source'
$destinationFiles = Get-ManifestFiles -ManifestRole $manifest.destination -Role 'destination'
$verifiedSource = Confirm-ManifestFiles -Files $sourceFiles -Role 'source'
$verifiedDestination = Confirm-ManifestFiles -Files $destinationFiles -Role 'destination'

$workspaceParent = Split-Path -Parent $workspaceResolved
$workspaceLeaf = Split-Path -Leaf $workspaceResolved
if ([string]::IsNullOrWhiteSpace($workspaceParent)) { throw 'The isolated workspace must have a parent directory.' }
New-Item -ItemType Directory -Path $workspaceParent -Force | Out-Null
$stagingRoot = Join-Path $workspaceParent (".{0}.preparing-{1}" -f $workspaceLeaf, [Guid]::NewGuid().ToString('N'))

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputDirectory = Join-Path $artifactRoot 'workspace-preparation'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("p0-isolated-workspace-preparation-{0}.json" -f $fileTimestamp)

$copyRecords = New-Object System.Collections.ArrayList
$completed = $false
try {
    Write-Host ''
    Write-Host '[2/4] Creating the disposable directory tree and copying verified media...' -ForegroundColor Cyan

    foreach ($relative in @('data_src', 'data_src\aligned', 'data_dst', 'data_dst\aligned', 'model', 'merged', 'merged_mask')) {
        New-Item -ItemType Directory -Path (Join-Path $stagingRoot $relative) -Force | Out-Null
    }

    $roleDefinitions = @(
        [ordered]@{ role = 'source'; prefix = 'src'; target = 'data_src'; files = $verifiedSource },
        [ordered]@{ role = 'destination'; prefix = 'dst'; target = 'data_dst'; files = $verifiedDestination }
    )

    foreach ($roleDefinition in $roleDefinitions) {
        $index = 0
        foreach ($file in @($roleDefinition.files)) {
            $index++
            $extension = [string]$file.extension
            $targetName = "{0}_{1:D4}{2}" -f $roleDefinition.prefix, $index, $extension
            $targetPath = Join-Path (Join-Path $stagingRoot $roleDefinition.target) $targetName

            Write-Host ("  [{0}] copy {1}/{2}: {3}" -f $roleDefinition.role, $index, @($roleDefinition.files).Count, $targetName) -ForegroundColor DarkCyan
            Copy-Item -LiteralPath $file.source_path -Destination $targetPath -ErrorAction Stop
            $copiedHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($copiedHash -ne [string]$file.sha256) {
                throw "Copied file hash mismatch: $targetPath"
            }

            [void]$copyRecords.Add([ordered]@{
                role = $roleDefinition.role
                source_path = $file.source_path
                target_relative_path = (Join-Path $roleDefinition.target $targetName)
                sha256 = $copiedHash
                size_bytes = [int64](Get-Item -LiteralPath $targetPath -Force).Length
            })
        }
    }

    $workspaceMarker = [ordered]@{
        schema_version = 1
        created_at_utc = $timestamp.ToString('o')
        repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
        profile_path = $profileResolved
        dataset_manifest = $manifestResolved
        workspace_root = $workspaceResolved
        source_file_count = $verifiedSource.Count
        destination_file_count = $verifiedDestination.Count
        copied_files = @($copyRecords | ForEach-Object { $_ })
        safety = [ordered]@{
            isolated_from_historical_runtime = $true
            historical_default_workspace_modified = $false
            deepfacelab_main_executed = $false
            tensorflow_imported = $false
            faces_extracted = $false
            training_started = $false
        }
    }
    $markerJson = $workspaceMarker | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $stagingRoot 'p0-workspace-manifest.json'), $markerJson, [System.Text.UTF8Encoding]::new($true))

    Move-Item -LiteralPath $stagingRoot -Destination $workspaceResolved -ErrorAction Stop
    $completed = $true
}
finally {
    if (-not $completed -and (Test-Path -LiteralPath $stagingRoot)) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$defaultWorkspaceAfter = Get-TreeSnapshot -Path $defaultWorkspace
$defaultWorkspaceUnchanged = $defaultWorkspaceBefore.metadata_sha256 -eq $defaultWorkspaceAfter.metadata_sha256
$repoStatusAfter = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
$repoUnchanged = $repoStatusBefore -eq $repoStatusAfter
$preparedWorkspaceSnapshot = Get-TreeSnapshot -Path $workspaceResolved

$status = if ($defaultWorkspaceUnchanged -and $repoUnchanged -and $verifiedSource.Count -gt 0 -and $verifiedDestination.Count -gt 0) {
    'passed'
}
else {
    'blocked_environment_changed'
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'p0_isolated_workspace_preparation'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    dataset_manifest = $manifestResolved
    workspace = [ordered]@{
        isolated_root = $workspaceResolved
        source_input_dir = Join-Path $workspaceResolved 'data_src'
        source_aligned_dir = Join-Path $workspaceResolved 'data_src\aligned'
        destination_input_dir = Join-Path $workspaceResolved 'data_dst'
        destination_aligned_dir = Join-Path $workspaceResolved 'data_dst\aligned'
        model_dir = Join-Path $workspaceResolved 'model'
        merged_dir = Join-Path $workspaceResolved 'merged'
        merged_mask_dir = Join-Path $workspaceResolved 'merged_mask'
        snapshot = $preparedWorkspaceSnapshot
    }
    copied_files = @($copyRecords | ForEach-Object { $_ })
    source_file_count = $verifiedSource.Count
    destination_file_count = $verifiedDestination.Count
    historical_default_workspace = [ordered]@{
        path = $defaultWorkspace
        before = $defaultWorkspaceBefore
        after = $defaultWorkspaceAfter
        unchanged = $defaultWorkspaceUnchanged
    }
    repository = [ordered]@{
        status_before = $repoStatusBefore
        status_after = $repoStatusAfter
        unchanged = $repoUnchanged
    }
    safety = [ordered]@{
        original_media_modified = $false
        existing_workspace_overwritten = $false
        media_copied_only_to_isolated_workspace = $true
        deepfacelab_main_executed = $false
        tensorflow_imported = $false
        faces_extracted = $false
        training_started = $false
        note = 'This stage verifies manifest hashes and prepares a new isolated workspace only. It does not execute DeepFaceLab or TensorFlow.'
    }
    next_action = $(if ($status -eq 'passed') { 'Review the prepared workspace, then run a separate time-limited face-extraction stage using explicit input and output paths.' } else { 'Do not run extraction. Review repository and historical default workspace changes.' })
}

$reportJson = $report | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($reportPath, $reportJson, [System.Text.UTF8Encoding]::new($true))

Write-Host ''
Write-Host '[3/4] Isolated workspace preparation result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Source files copied: {0}" -f $verifiedSource.Count)
Write-Host ("Destination files copied: {0}" -f $verifiedDestination.Count)
Write-Host ("Historical default workspace unchanged: {0}" -f $defaultWorkspaceUnchanged)
Write-Host ("Repository unchanged: {0}" -f $repoUnchanged)
Write-Host ("Isolated workspace: {0}" -f $workspaceResolved)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ''
Write-Host '[4/4] Safety boundary' -ForegroundColor Cyan
Write-Host 'No faces were extracted. TensorFlow, DeepFaceLab main.py, models, and training were not started.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    isolated_workspace = $workspaceResolved
    source_file_count = $verifiedSource.Count
    destination_file_count = $verifiedDestination.Count
    historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
    repository_unchanged = $repoUnchanged
}

if ($status -ne 'passed') { exit 1 }
exit 0
