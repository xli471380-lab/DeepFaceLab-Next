[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$SourceMediaPath,
    [Parameter(Mandatory = $true)][string]$DestinationMediaPath,
    [switch]$AuthorizationConfirmed,
    [ValidateRange(1, 5000)][int]$MaxFilesPerRole = 500,
    [ValidateRange(1, 8192)][int]$MaxTotalMiBPerRole = 2048,
    [ValidateRange(0, 100)][int]$MetadataSampleLimitPerRole = 20
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

function Get-WorkspaceSnapshot {
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

function Quote-NativeArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-NativeCaptureWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @(),
        [ValidateRange(1, 120)][int]$TimeoutSeconds = 15
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = (@($Arguments | ForEach-Object { Quote-NativeArgument -Value ([string]$_) }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false

    try {
        $started = $process.Start()
        if (-not $started) {
            return [ordered]@{ exit_code = -1; timed_out = $false; stdout = ''; stderr = 'Process did not start.' }
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $finished) {
            try { $process.Kill() } catch {}
            try { $process.WaitForExit() } catch {}
            $stdout = try { [string]$stdoutTask.Result } catch { '' }
            $stderr = try { [string]$stderrTask.Result } catch { $_.Exception.Message }
            return [ordered]@{ exit_code = -408; timed_out = $true; stdout = $stdout; stderr = $stderr }
        }

        $stdout = try { [string]$stdoutTask.Result } catch { '' }
        $stderr = try { [string]$stderrTask.Result } catch { $_.Exception.Message }
        $exitCode = try { [int]$process.ExitCode } catch { -1 }
        return [ordered]@{ exit_code = $exitCode; timed_out = $false; stdout = $stdout; stderr = $stderr }
    }
    catch {
        return [ordered]@{ exit_code = -1; timed_out = $false; stdout = ''; stderr = $_.Exception.ToString() }
    }
    finally {
        if ($started) {
            try {
                if (-not $process.HasExited) { $process.Kill() }
            }
            catch {}
        }
        $process.Dispose()
    }
}

function Get-MediaFiles {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    $item = Get-Item -LiteralPath $resolved.Path -Force -ErrorAction Stop

    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Force -Recurse -ErrorAction Stop | Sort-Object FullName)
    }

    return @($item)
}

function Get-RoleInventory {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [AllowNull()][string]$FfprobePath
    )

    $allFiles = @(Get-MediaFiles -Path $RootPath)
    $allowedExtensions = @('.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v', '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.tif', '.tiff')
    $recognized = @($allFiles | Where-Object { $allowedExtensions -contains $_.Extension.ToLowerInvariant() })
    $ignored = @($allFiles | Where-Object { $allowedExtensions -notcontains $_.Extension.ToLowerInvariant() })

    if ($recognized.Count -eq 0) { throw "No recognized media files were found for role '$Role': $RootPath" }
    if ($recognized.Count -gt $MaxFilesPerRole) {
        throw "Role '$Role' contains $($recognized.Count) media files, above the limit of $MaxFilesPerRole."
    }

    $totalBytes = [int64]0
    foreach ($file in $recognized) { $totalBytes += [int64]$file.Length }
    $maxBytes = [int64]$MaxTotalMiBPerRole * 1MB
    if ($totalBytes -gt $maxBytes) {
        throw "Role '$Role' contains $totalBytes bytes, above the limit of $maxBytes bytes."
    }

    $rootItem = Get-Item -LiteralPath (Resolve-Path -LiteralPath $RootPath).Path -Force
    $rootBase = if ($rootItem.PSIsContainer) { $rootItem.FullName.TrimEnd('\') } else { $rootItem.DirectoryName.TrimEnd('\') }

    $records = New-Object System.Collections.ArrayList
    $index = 0
    foreach ($file in $recognized) {
        $index++
        Write-Host ("  [{0}] hashing {1}/{2}: {3}" -f $Role, $index, $recognized.Count, $file.Name) -ForegroundColor DarkCyan
        $relative = if ($rootItem.PSIsContainer) {
            $file.FullName.Substring($rootBase.Length).TrimStart('\')
        }
        else {
            $file.Name
        }

        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        $kind = if (@('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.tif', '.tiff') -contains $file.Extension.ToLowerInvariant()) { 'image' } else { 'video' }

        $metadata = $null
        if (-not [string]::IsNullOrWhiteSpace($FfprobePath) -and $index -le $MetadataSampleLimitPerRole) {
            $probe = Invoke-NativeCaptureWithTimeout `
                -Executable $FfprobePath `
                -Arguments @(
                    '-v', 'error',
                    '-show_entries', 'format=duration,format_name,size:stream=index,codec_type,codec_name,width,height,r_frame_rate,avg_frame_rate',
                    '-of', 'json',
                    $file.FullName
                ) `
                -TimeoutSeconds 15

            $parsed = $null
            $parseError = $null
            if ($probe.exit_code -eq 0 -and -not [string]::IsNullOrWhiteSpace($probe.stdout)) {
                try { $parsed = $probe.stdout | ConvertFrom-Json }
                catch { $parseError = $_.Exception.Message }
            }

            $metadata = [ordered]@{
                sampled = $true
                exit_code = $probe.exit_code
                timed_out = $probe.timed_out
                parse_error = $parseError
                data = $parsed
                stderr = $probe.stderr
            }
        }

        [void]$records.Add([ordered]@{
            relative_path = $relative
            full_path = $file.FullName
            extension = $file.Extension.ToLowerInvariant()
            media_kind = $kind
            size_bytes = [int64]$file.Length
            last_write_time_utc = $file.LastWriteTimeUtc.ToString('o')
            sha256 = $hash
            metadata = $metadata
        })
    }

    return [ordered]@{
        role = $Role
        root_path = $rootItem.FullName
        recognized_file_count = $recognized.Count
        ignored_file_count = $ignored.Count
        ignored_file_names_sample = @($ignored | Select-Object -First 20 | ForEach-Object { $_.Name })
        total_bytes = $totalBytes
        max_files_limit = $MaxFilesPerRole
        max_total_mib_limit = $MaxTotalMiBPerRole
        metadata_sample_limit = $MetadataSampleLimitPerRole
        files = @($records | ForEach-Object { $_ })
    }
}

if (-not $AuthorizationConfirmed) {
    throw 'Authorization confirmation was not supplied. Use the stage-11 BAT and confirm that both identities are authorized and distinct.'
}

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$runtimeRoot = Normalize-FullPath -Path (Get-ProfileValue 'RuntimeRoot')
$workspacePath = Normalize-FullPath -Path (Get-ProfileValue 'WorkspacePath')
$ffmpegExe = Get-ProfileValue 'FFmpegExe'

$sourceResolved = Normalize-FullPath -Path (Resolve-Path -LiteralPath $SourceMediaPath -ErrorAction Stop).Path
$destinationResolved = Normalize-FullPath -Path (Resolve-Path -LiteralPath $DestinationMediaPath -ErrorAction Stop).Path
$repoRootNormalized = Normalize-FullPath -Path $repoRoot

if ($sourceResolved.Equals($destinationResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source and destination media paths must be different.'
}
if ((Test-PathInside -Candidate $sourceResolved -Parent $destinationResolved) -or (Test-PathInside -Candidate $destinationResolved -Parent $sourceResolved)) {
    throw 'Source and destination media paths must not contain one another.'
}

foreach ($rolePath in @($sourceResolved, $destinationResolved)) {
    if (Test-PathInside -Candidate $rolePath -Parent $repoRootNormalized) {
        throw "Dataset media must stay outside the Git repository: $rolePath"
    }
    if (Test-PathInside -Candidate $rolePath -Parent $runtimeRoot) {
        throw "Dataset media must stay outside the historical runtime and workspace: $rolePath"
    }
}

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) {
    throw 'The repository working tree is not clean. Commit, stash, or remove unrelated changes before creating the P0 dataset manifest.'
}

$ffprobePath = $null
$ffprobeCandidate = Join-Path (Split-Path -Parent $ffmpegExe) 'ffprobe.exe'
if (Test-Path -LiteralPath $ffprobeCandidate -PathType Leaf) { $ffprobePath = $ffprobeCandidate }

$workspaceBefore = Get-WorkspaceSnapshot -Path $workspacePath
$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\dataset-preflight" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("p0-authorized-dataset-manifest-{0}.json" -f $fileTimestamp)

Write-Host ''
Write-Host '[1/4] Preconditions passed.' -ForegroundColor Cyan
Write-Host ("Profile: {0}" -f $profileResolved)
Write-Host ("Source media: {0}" -f $sourceResolved)
Write-Host ("Destination media: {0}" -f $destinationResolved)
Write-Host ("ffprobe: {0}" -f $(if ($null -eq $ffprobePath) { 'not available; metadata sampling will be skipped' } else { $ffprobePath }))
Write-Host ''
Write-Host '[2/4] Building immutable file inventories and SHA-256 hashes...' -ForegroundColor Cyan

$sourceInventory = Get-RoleInventory -Role 'source' -RootPath $sourceResolved -FfprobePath $ffprobePath
$destinationInventory = Get-RoleInventory -Role 'destination' -RootPath $destinationResolved -FfprobePath $ffprobePath

$sourceHashes = @($sourceInventory.files | ForEach-Object { [string]$_.sha256 })
$destinationHashes = @($destinationInventory.files | ForEach-Object { [string]$_.sha256 })
$overlapHashes = @($sourceHashes | Where-Object { $destinationHashes -contains $_ } | Sort-Object -Unique)
if ($overlapHashes.Count -gt 0) {
    throw 'Source and destination inventories contain one or more identical files. Use separate authorized identity datasets.'
}

$workspaceAfter = Get-WorkspaceSnapshot -Path $workspacePath
$workspaceUnchanged = $workspaceBefore.metadata_sha256 -eq $workspaceAfter.metadata_sha256
$repoStatusAfter = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
$repoUnchanged = $repoStatusBefore -eq $repoStatusAfter

$status = if ($workspaceUnchanged -and $repoUnchanged) { 'passed' } else { 'blocked_environment_changed' }

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'p0_authorized_dataset_preflight'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    authorization = [ordered]@{
        confirmed_by_user = [bool]$AuthorizationConfirmed
        separate_source_and_destination_identities_confirmed = [bool]$AuthorizationConfirmed
        authorized_non_public_media_required = $true
        public_figure_or_unconsented_media_allowed = $false
    }
    isolation = [ordered]@{
        repository_root = $repoRootNormalized
        runtime_root = $runtimeRoot
        workspace_path = $workspacePath
        media_paths_outside_repository = $true
        media_paths_outside_runtime = $true
        source_destination_paths_distinct = $true
        identical_file_hash_overlap_count = $overlapHashes.Count
    }
    tools = [ordered]@{
        ffmpeg_exe = $ffmpegExe
        ffprobe_exe = $ffprobePath
        ffprobe_available = $null -ne $ffprobePath
    }
    source = $sourceInventory
    destination = $destinationInventory
    repository = [ordered]@{
        status_before = $repoStatusBefore
        status_after = $repoStatusAfter
        unchanged = $repoUnchanged
    }
    workspace = [ordered]@{
        before = $workspaceBefore
        after = $workspaceAfter
        unchanged = $workspaceUnchanged
    }
    safety = [ordered]@{
        media_copied = $false
        frames_extracted = $false
        faces_detected = $false
        faces_aligned = $false
        tensorflow_imported = $false
        deepfacelab_main_executed = $false
        training_started = $false
        workspace_modified_intentionally = $false
        repository_media_tracked = $false
        note = 'This preflight reads metadata and hashes only. It does not copy media, extract frames or faces, import TensorFlow, or execute DeepFaceLab.'
    }
    next_action = $(if ($status -eq 'passed') { 'Review the manifest and create a separately bounded frame-extraction stage. Do not start training yet.' } else { 'Resolve the environment change before any media is copied into the historical workspace.' })
}

$reportJson = $report | ConvertTo-Json -Depth 14
[System.IO.File]::WriteAllText($reportPath, $reportJson, [System.Text.UTF8Encoding]::new($true))

Write-Host ''
Write-Host '[3/4] Dataset preflight result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Source files: {0}; bytes: {1}" -f $sourceInventory.recognized_file_count, $sourceInventory.total_bytes)
Write-Host ("Destination files: {0}; bytes: {1}" -f $destinationInventory.recognized_file_count, $destinationInventory.total_bytes)
Write-Host ("Identical hash overlap: {0}" -f $overlapHashes.Count)
Write-Host ("Repository unchanged: {0}" -f $repoUnchanged)
Write-Host ("Workspace unchanged: {0}" -f $workspaceUnchanged)
Write-Host ("Manifest: {0}" -f $reportPath)
Write-Host ''
Write-Host '[4/4] Safety boundary' -ForegroundColor Cyan
Write-Host 'No media was copied. No frames or faces were extracted. TensorFlow and DeepFaceLab were not started.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    source_file_count = $sourceInventory.recognized_file_count
    destination_file_count = $destinationInventory.recognized_file_count
    identical_hash_overlap_count = $overlapHashes.Count
    repository_unchanged = $repoUnchanged
    workspace_unchanged = $workspaceUnchanged
    ffprobe_available = $null -ne $ffprobePath
}

if ($status -ne 'passed') { exit 1 }
exit 0
