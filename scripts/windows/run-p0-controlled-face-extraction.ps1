[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [switch]$ExtractConfirmed,
    [ValidateRange(60, 1800)][int]$TimeoutSecondsPerRole = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved
$validatorScript = Join-Path $PSScriptRoot 'validate-p0-aligned-faces.py'

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

function Quote-NativeArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
}

function Limit-Text {
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [int]$MaximumCharacters = 24000
    )
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $MaximumCharacters) { return $Text }
    return $Text.Substring($Text.Length - $MaximumCharacters) + "`n...[tail retained]"
}

function Invoke-IsolatedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $pythonExe
    $startInfo.Arguments = (@($Arguments | ForEach-Object { Quote-NativeArgument -Value ([string]$_) }) -join ' ')
    $startInfo.WorkingDirectory = $deepFaceLabRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['PATH'] = $isolatedPath
    foreach ($name in @('PYTHONHOME', 'PYTHONPATH', 'CUDA_PATH', 'CUDA_HOME', 'CUDNN_PATH', 'CUDA_VISIBLE_DEVICES')) {
        $startInfo.EnvironmentVariables.Remove($name)
    }
    $startInfo.EnvironmentVariables['PYTHONNOUSERSITE'] = '1'
    $startInfo.EnvironmentVariables['PYTHONUNBUFFERED'] = '1'
    $startInfo.EnvironmentVariables['TF_FORCE_GPU_ALLOW_GROWTH'] = 'true'
    $startInfo.EnvironmentVariables['TF_CPP_MIN_LOG_LEVEL'] = '0'
    $startInfo.EnvironmentVariables['TF_ENABLE_ONEDNN_OPTS'] = '0'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    $timedOut = $false
    $stdout = ''
    $stderr = ''
    $exitCode = $null

    try {
        $started = $process.Start()
        if (-not $started) { throw "Process did not start: $Label" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $startedAt = Get-Date
        $nextProgress = 10

        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            $process.Refresh()
            $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
            if ($elapsed -ge $nextProgress) {
                Write-Host ("  {0}: elapsed {1}s / timeout {2}s" -f $Label, $elapsed, $TimeoutSeconds) -ForegroundColor DarkCyan
                $nextProgress += 10
            }
            if ($elapsed -ge $TimeoutSeconds) {
                $timedOut = $true
                Write-Host ("  {0}: timeout reached; stopping the process tree." -f $Label) -ForegroundColor Yellow
                Stop-ProcessTree -ProcessId $process.Id
                break
            }
        }

        try { $process.WaitForExit() } catch {}
        try { $stdout = [string]$stdoutTask.Result } catch { $stdout = '' }
        try { $stderr = [string]$stderrTask.Result } catch { $stderr = $_.Exception.ToString() }
        if (-not $timedOut) {
            try { $exitCode = [int]$process.ExitCode } catch { $exitCode = $null }
        }
    }
    catch {
        $stderr = $_.Exception.ToString()
    }
    finally {
        if ($started) {
            try {
                $process.Refresh()
                if (-not $process.HasExited) { Stop-ProcessTree -ProcessId $process.Id }
            }
            catch {}
        }
        $process.Dispose()
    }

    return [ordered]@{
        label = $Label
        timed_out = $timedOut
        exit_code = $exitCode
        stdout = $stdout
        stderr = $stderr
    }
}

function Convert-ValidationResult {
    param([AllowEmptyString()][string]$Text)
    $match = [regex]::Match($Text, '(?s)__DFLNEXT_FACESET_VALIDATION_JSON_BEGIN__\s*(.*?)\s*__DFLNEXT_FACESET_VALIDATION_JSON_END__')
    if (-not $match.Success) {
        return [ordered]@{ value = $null; error = 'Faceset validation sentinel JSON markers were not found.' }
    }
    try {
        return [ordered]@{ value = ($match.Groups[1].Value | ConvertFrom-Json); error = $null }
    }
    catch {
        return [ordered]@{ value = $null; error = $_.Exception.Message }
    }
}

function Confirm-CopiedInputs {
    param(
        [Parameter(Mandatory = $true)]$Records,
        [Parameter(Mandatory = $true)][string]$Role
    )
    $verified = New-Object System.Collections.ArrayList
    foreach ($record in @($Records)) {
        $relative = [string]$record.target_relative_path
        $path = Join-Path $workspaceResolved $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing isolated workspace input for $Role: $path" }
        $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actualHash -ne [string]$record.sha256) { throw "Isolated workspace input hash mismatch for $Role: $path" }
        [void]$verified.Add([ordered]@{
            role = $Role
            path = $path
            name = (Split-Path -Leaf $path)
            sha256 = $actualHash
            size_bytes = [int64](Get-Item -LiteralPath $path -Force).Length
        })
    }
    return @($verified | ForEach-Object { $_ })
}

function Confirm-InputsUnchanged {
    param([Parameter(Mandatory = $true)]$VerifiedRecords)
    foreach ($record in @($VerifiedRecords)) {
        if (-not (Test-Path -LiteralPath $record.path -PathType Leaf)) { return $false }
        $actualHash = (Get-FileHash -LiteralPath $record.path -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actualHash -ne [string]$record.sha256) { return $false }
    }
    return $true
}

function Invoke-RoleExtraction {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$InputDirectory,
        [Parameter(Mandatory = $true)][string]$StagingDirectory,
        [Parameter(Mandatory = $true)][string]$LogPrefix
    )

    New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
    Write-Host ("  [{0}] starting S3FD whole-face extraction on GPU 0..." -f $Role) -ForegroundColor Cyan

    $extractArguments = @(
        $mainPy,
        'extract',
        '--detector', 's3fd',
        '--input-dir', $InputDirectory,
        '--output-dir', $StagingDirectory,
        '--no-output-debug',
        '--face-type', 'whole_face',
        '--max-faces-from-image', '1',
        '--image-size', '512',
        '--jpeg-quality', '90',
        '--force-gpu-idxs', '0'
    )
    $extractProcess = Invoke-IsolatedProcess -Label ("{0}-extract" -f $Role) -Arguments $extractArguments -TimeoutSeconds $TimeoutSecondsPerRole
    $extractStdoutPath = Join-Path $outputDirectory ("{0}.extract.stdout.txt" -f $LogPrefix)
    $extractStderrPath = Join-Path $outputDirectory ("{0}.extract.stderr.txt" -f $LogPrefix)
    [System.IO.File]::WriteAllText($extractStdoutPath, [string]$extractProcess.stdout, [System.Text.UTF8Encoding]::new($true))
    [System.IO.File]::WriteAllText($extractStderrPath, [string]$extractProcess.stderr, [System.Text.UTF8Encoding]::new($true))

    $validatorProcess = $null
    $validatorParse = [ordered]@{ value = $null; error = 'Validator was not run because extraction did not complete successfully.' }
    $validatorStdoutPath = Join-Path $outputDirectory ("{0}.validate.stdout.txt" -f $LogPrefix)
    $validatorStderrPath = Join-Path $outputDirectory ("{0}.validate.stderr.txt" -f $LogPrefix)

    if (-not $extractProcess.timed_out -and $null -ne $extractProcess.exit_code -and [int]$extractProcess.exit_code -eq 0) {
        Write-Host ("  [{0}] validating DFLJPG metadata and source mapping..." -f $Role) -ForegroundColor Cyan
        $validatorArguments = @($validatorScript, $deepFaceLabRoot, $InputDirectory, $StagingDirectory)
        $validatorProcess = Invoke-IsolatedProcess -Label ("{0}-validate" -f $Role) -Arguments $validatorArguments -TimeoutSeconds 60
        [System.IO.File]::WriteAllText($validatorStdoutPath, [string]$validatorProcess.stdout, [System.Text.UTF8Encoding]::new($true))
        [System.IO.File]::WriteAllText($validatorStderrPath, [string]$validatorProcess.stderr, [System.Text.UTF8Encoding]::new($true))
        $validatorParse = Convert-ValidationResult -Text ([string]$validatorProcess.stdout)
    }
    else {
        [System.IO.File]::WriteAllText($validatorStdoutPath, '', [System.Text.UTF8Encoding]::new($true))
        [System.IO.File]::WriteAllText($validatorStderrPath, '', [System.Text.UTF8Encoding]::new($true))
    }

    $validatorStatus = if ($null -ne $validatorParse.value) { [string]$validatorParse.value.status } else { '' }
    $passed = (
        -not $extractProcess.timed_out -and
        $null -ne $extractProcess.exit_code -and
        [int]$extractProcess.exit_code -eq 0 -and
        $null -ne $validatorProcess -and
        -not $validatorProcess.timed_out -and
        $null -ne $validatorProcess.exit_code -and
        [int]$validatorProcess.exit_code -eq 0 -and
        $null -eq $validatorParse.error -and
        $validatorStatus -eq 'passed'
    )

    $imagesFound = $null
    $facesDetected = $null
    $imagesMatch = [regex]::Matches([string]$extractProcess.stdout, 'Images found:\s*(\d+)')
    if ($imagesMatch.Count -gt 0) { $imagesFound = [int]$imagesMatch[$imagesMatch.Count - 1].Groups[1].Value }
    $facesMatch = [regex]::Matches([string]$extractProcess.stdout, 'Faces detected:\s*(\d+)')
    if ($facesMatch.Count -gt 0) { $facesDetected = [int]$facesMatch[$facesMatch.Count - 1].Groups[1].Value }

    return [ordered]@{
        role = $Role
        status = $(if ($passed) { 'passed' } elseif ($extractProcess.timed_out) { 'blocked_timeout' } elseif ($null -ne $validatorParse.error) { 'blocked_invalid_validation_output' } else { 'blocked_extraction_or_validation' })
        input_dir = $InputDirectory
        staging_output_dir = $StagingDirectory
        extraction = [ordered]@{
            timed_out = $extractProcess.timed_out
            exit_code = $extractProcess.exit_code
            images_found = $imagesFound
            faces_detected = $facesDetected
            stdout_file = $extractStdoutPath
            stderr_file = $extractStderrPath
            stderr_tail = Limit-Text -Text ([string]$extractProcess.stderr)
        }
        validation = [ordered]@{
            timed_out = $(if ($null -eq $validatorProcess) { $false } else { [bool]$validatorProcess.timed_out })
            exit_code = $(if ($null -eq $validatorProcess) { $null } else { $validatorProcess.exit_code })
            parse_error = $validatorParse.error
            result = $validatorParse.value
            stdout_file = $validatorStdoutPath
            stderr_file = $validatorStderrPath
            stderr_tail = $(if ($null -eq $validatorProcess) { '' } else { Limit-Text -Text ([string]$validatorProcess.stderr) })
        }
    }
}

if (-not $ExtractConfirmed) {
    throw 'Controlled extraction confirmation was not supplied. Use the step-13 BAT and confirm the bounded synthetic-data extraction.'
}
if (-not (Test-Path -LiteralPath $validatorScript -PathType Leaf)) { throw "Aligned faces validator was not found: $validatorScript" }

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$runtimeRoot = Normalize-FullPath -Path (Get-ProfileValue 'RuntimeRoot')
$pythonExe = Normalize-FullPath -Path (Get-ProfileValue 'PythonExe')
$deepFaceLabRoot = Normalize-FullPath -Path (Get-ProfileValue 'DeepFaceLabRoot')
$mainPy = Normalize-FullPath -Path (Get-ProfileValue 'MainPy')
$defaultWorkspace = Normalize-FullPath -Path (Get-ProfileValue 'WorkspacePath')
$workspaceResolved = Normalize-FullPath -Path (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$repoRootNormalized = Normalize-FullPath -Path $repoRoot

foreach ($requiredPath in @($runtimeRoot, $pythonExe, $deepFaceLabRoot, $mainPy, $defaultWorkspace, $workspaceResolved)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required path does not exist: $requiredPath" }
}
if (Test-PathInside -Candidate $workspaceResolved -Parent $repoRootNormalized) { throw 'The isolated P0 workspace must stay outside the Git repository.' }
if (Test-PathInside -Candidate $workspaceResolved -Parent $runtimeRoot) { throw 'The isolated P0 workspace must stay outside the historical runtime.' }

$workspaceMarkerPath = Join-Path $workspaceResolved 'p0-workspace-manifest.json'
if (-not (Test-Path -LiteralPath $workspaceMarkerPath -PathType Leaf)) { throw "P0 workspace marker was not found: $workspaceMarkerPath" }
$workspaceMarker = Get-Content -LiteralPath $workspaceMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
if ([System.IO.Path]::GetFullPath([string]$workspaceMarker.profile_path) -ne [System.IO.Path]::GetFullPath($profileResolved)) { throw 'The isolated workspace belongs to a different local profile.' }
if ([System.IO.Path]::GetFullPath([string]$workspaceMarker.workspace_root) -ne [System.IO.Path]::GetFullPath($workspaceResolved)) { throw 'The workspace marker root does not match the requested workspace.' }

$artifactRoot = Join-Path $repoRoot ("artifacts\p0\{0}\{1}" -f $machineId, $environmentId)
$workspacePreparationReport = Get-ChildItem -LiteralPath (Join-Path $artifactRoot 'workspace-preparation') -Filter 'p0-isolated-workspace-preparation-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $workspacePreparationReport) { throw 'A passed step-12 workspace preparation report is required.' }
$step12 = Get-Content -LiteralPath $workspacePreparationReport.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string]$step12.status -ne 'passed') { throw 'The latest step-12 report is not passed.' }
if ([System.IO.Path]::GetFullPath([string]$step12.workspace.isolated_root) -ne [System.IO.Path]::GetFullPath($workspaceResolved)) { throw 'The latest step-12 report belongs to a different isolated workspace.' }

$gpuReport = Get-ChildItem -LiteralPath (Join-Path $artifactRoot 'tensorflow-gpu-probe') -Filter 'legacy-tensorflow-gpu-visibility-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $gpuReport) { throw 'A passed step-10 TensorFlow/GPU visibility report is required.' }
$step10 = Get-Content -LiteralPath $gpuReport.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string]$step10.status -ne 'passed') { throw 'The latest step-10 TensorFlow/GPU visibility report is not passed.' }

$sourceInput = Join-Path $workspaceResolved 'data_src'
$destinationInput = Join-Path $workspaceResolved 'data_dst'
$sourceAligned = Join-Path $sourceInput 'aligned'
$destinationAligned = Join-Path $destinationInput 'aligned'
foreach ($directory in @($sourceInput, $destinationInput, $sourceAligned, $destinationAligned)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Required workspace directory is missing: $directory" }
}
foreach ($alignedDirectory in @($sourceAligned, $destinationAligned)) {
    if (@(Get-ChildItem -LiteralPath $alignedDirectory -Force -ErrorAction Stop).Count -ne 0) {
        throw "Aligned output directory must be empty before step 13; nothing will be deleted: $alignedDirectory"
    }
}

$sourceMarkerRecords = @($workspaceMarker.copied_files | Where-Object { [string]$_.role -eq 'source' })
$destinationMarkerRecords = @($workspaceMarker.copied_files | Where-Object { [string]$_.role -eq 'destination' })
if ($sourceMarkerRecords.Count -eq 0 -or $destinationMarkerRecords.Count -eq 0) { throw 'Workspace marker contains no copied source or destination files.' }
$verifiedSourceInputs = Confirm-CopiedInputs -Records $sourceMarkerRecords -Role 'source'
$verifiedDestinationInputs = Confirm-CopiedInputs -Records $destinationMarkerRecords -Role 'destination'

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) { throw 'The Git working tree is not clean.' }
$defaultWorkspaceBefore = Get-TreeSnapshot -Path $defaultWorkspace

$internalRoot = Join-Path $runtimeRoot '_internal'
$pythonRoot = Split-Path -Parent $pythonExe
$dllPatterns = @('cudart64*.dll','cudnn64*.dll','cublas64*.dll','cublasLt64*.dll','cufft64*.dll','curand64*.dll','cusolver64*.dll','cusparse64*.dll','nvrtc64*.dll','nvrtc-builtins64*.dll','zlibwapi.dll')
$dllFilesList = New-Object System.Collections.ArrayList
foreach ($pattern in $dllPatterns) {
    foreach ($file in @(Get-ChildItem -LiteralPath $internalRoot -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue)) { [void]$dllFilesList.Add($file) }
}
$dllFiles = @($dllFilesList | Sort-Object FullName -Unique)
$dllDirectories = @($dllFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
$candidatePaths = @($pythonRoot, (Join-Path $pythonRoot 'Scripts'), $internalRoot) + @($dllDirectories) + @((Join-Path $env:SystemRoot 'System32'), $env:SystemRoot)
$pathEntriesList = New-Object System.Collections.ArrayList
foreach ($candidate in $candidatePaths) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate) -and -not $pathEntriesList.Contains($candidate)) { [void]$pathEntriesList.Add($candidate) }
}
$pathEntries = @($pathEntriesList)
$isolatedPath = $pathEntries -join ';'

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputDirectory = Join-Path $artifactRoot 'face-extraction'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("p0-controlled-face-extraction-{0}.json" -f $fileTimestamp)
$sourceStaging = Join-Path $sourceInput ('.aligned-p0-staging-' + [Guid]::NewGuid().ToString('N'))
$destinationStaging = Join-Path $destinationInput ('.aligned-p0-staging-' + [Guid]::NewGuid().ToString('N'))

Write-Host ''
Write-Host '[1/4] Preconditions and immutable input hashes passed.' -ForegroundColor Cyan
Write-Host ("Profile: {0}" -f $profileResolved)
Write-Host ("Isolated workspace: {0}" -f $workspaceResolved)
Write-Host ("Source inputs: {0}; destination inputs: {1}" -f $verifiedSourceInputs.Count, $verifiedDestinationInputs.Count)
Write-Host ("Bundled CUDA/cuDNN DLL files selected: {0}" -f $dllFiles.Count)
Write-Host ("Timeout per identity: {0} seconds" -f $TimeoutSecondsPerRole)
Write-Host ''
Write-Host '[2/4] Running bounded S3FD whole-face extraction into temporary directories...' -ForegroundColor Cyan

$sourceResult = $null
$destinationResult = $null
$commitSucceeded = $false
$status = 'blocked_not_started'
$inputsUnchanged = $false
$defaultWorkspaceUnchanged = $false
$repoUnchanged = $false

try {
    $sourceResult = Invoke-RoleExtraction -Role 'source' -InputDirectory $sourceInput -StagingDirectory $sourceStaging -LogPrefix ("{0}-source" -f $fileTimestamp)
    if ([string]$sourceResult.status -eq 'passed') {
        $destinationResult = Invoke-RoleExtraction -Role 'destination' -InputDirectory $destinationInput -StagingDirectory $destinationStaging -LogPrefix ("{0}-destination" -f $fileTimestamp)
    }

    $inputsUnchanged = (Confirm-InputsUnchanged -VerifiedRecords $verifiedSourceInputs) -and (Confirm-InputsUnchanged -VerifiedRecords $verifiedDestinationInputs)
    $defaultWorkspaceAfterExtraction = Get-TreeSnapshot -Path $defaultWorkspace
    $defaultWorkspaceUnchanged = $defaultWorkspaceBefore.metadata_sha256 -eq $defaultWorkspaceAfterExtraction.metadata_sha256
    $repoStatusAfterExtraction = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
    $repoUnchanged = $repoStatusBefore -eq $repoStatusAfterExtraction

    if ([string]$sourceResult.status -ne 'passed') {
        $status = 'blocked_source_extraction'
    }
    elseif ($null -eq $destinationResult -or [string]$destinationResult.status -ne 'passed') {
        $status = 'blocked_destination_extraction'
    }
    elseif (-not $inputsUnchanged) {
        $status = 'blocked_input_changed'
    }
    elseif (-not $defaultWorkspaceUnchanged) {
        $status = 'blocked_historical_workspace_changed'
    }
    elseif (-not $repoUnchanged) {
        $status = 'blocked_repository_changed'
    }
    else {
        Remove-Item -LiteralPath $sourceAligned -Force -ErrorAction Stop
        Remove-Item -LiteralPath $destinationAligned -Force -ErrorAction Stop
        try {
            Move-Item -LiteralPath $sourceStaging -Destination $sourceAligned -ErrorAction Stop
            Move-Item -LiteralPath $destinationStaging -Destination $destinationAligned -ErrorAction Stop
            $commitSucceeded = $true
            $status = 'passed'
        }
        catch {
            if ((Test-Path -LiteralPath $sourceAligned) -and -not (Test-Path -LiteralPath $sourceStaging)) { Move-Item -LiteralPath $sourceAligned -Destination $sourceStaging -ErrorAction SilentlyContinue }
            if ((Test-Path -LiteralPath $destinationAligned) -and -not (Test-Path -LiteralPath $destinationStaging)) { Move-Item -LiteralPath $destinationAligned -Destination $destinationStaging -ErrorAction SilentlyContinue }
            if (-not (Test-Path -LiteralPath $sourceAligned)) { New-Item -ItemType Directory -Path $sourceAligned -Force | Out-Null }
            if (-not (Test-Path -LiteralPath $destinationAligned)) { New-Item -ItemType Directory -Path $destinationAligned -Force | Out-Null }
            $status = 'blocked_output_commit_failed'
        }
    }
}
finally {
    if (-not $commitSucceeded) {
        foreach ($staging in @($sourceStaging, $destinationStaging)) {
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

$sourceAlignedFiles = if (Test-Path -LiteralPath $sourceAligned) { @(Get-ChildItem -LiteralPath $sourceAligned -Filter '*.jpg' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name) } else { @() }
$destinationAlignedFiles = if (Test-Path -LiteralPath $destinationAligned) { @(Get-ChildItem -LiteralPath $destinationAligned -Filter '*.jpg' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name) } else { @() }

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'p0_controlled_face_extraction'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    workspace_root = $workspaceResolved
    preconditions = [ordered]@{
        step10_report = $gpuReport.FullName
        step10_status = [string]$step10.status
        step12_report = $workspacePreparationReport.FullName
        step12_status = [string]$step12.status
        workspace_marker = $workspaceMarkerPath
        authorization_inherited_from_dataset_manifest = $true
    }
    parameters = [ordered]@{
        detector = 's3fd'
        face_type = 'whole_face'
        max_faces_from_image = 1
        image_size = 512
        jpeg_quality = 90
        gpu_index = 0
        output_debug = $false
        timeout_seconds_per_role = $TimeoutSecondsPerRole
    }
    isolation = [ordered]@{
        system_cuda_environment_cleared = $true
        isolated_path_entries = @($pathEntries)
        bundled_dll_file_count = $dllFiles.Count
        temporary_output_then_commit = $true
        existing_aligned_output_deleted = $false
    }
    source = $sourceResult
    destination = $destinationResult
    outputs = [ordered]@{
        commit_succeeded = $commitSucceeded
        source_aligned_dir = $sourceAligned
        destination_aligned_dir = $destinationAligned
        source_aligned_count = $sourceAlignedFiles.Count
        destination_aligned_count = $destinationAlignedFiles.Count
        source_files = @($sourceAlignedFiles | ForEach-Object { [ordered]@{ name = $_.Name; size_bytes = [int64]$_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } })
        destination_files = @($destinationAlignedFiles | ForEach-Object { [ordered]@{ name = $_.Name; size_bytes = [int64]$_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } })
    }
    environment_checks = [ordered]@{
        isolated_inputs_unchanged = $inputsUnchanged
        historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
        repository_unchanged = $repoUnchanged
    }
    safety = [ordered]@{
        authorized_synthetic_inputs_only = $true
        deepfacelab_main_executed = $true
        tensorflow_imported = $true
        face_detection_and_alignment_executed = $true
        manual_extraction_started = $false
        model_created = $false
        training_started = $false
        merge_started = $false
        dfm_export_started = $false
        historical_default_workspace_modified = $false
        note = 'This stage runs S3FD detection and whole-face alignment only on the isolated authorized synthetic workspace. It does not create or train a model.'
    }
    next_action = $(if ($status -eq 'passed') { 'Review the six aligned outputs, then design a separately bounded short-training stage. Do not start training yet.' } else { 'Review extraction and validator logs. Do not start training.' })
}

if ($status -eq 'passed') {
    $workspaceExtractionManifest = Join-Path $workspaceResolved 'p0-face-extraction-manifest.json'
    $workspaceReport = [ordered]@{
        schema_version = 1
        generated_at_utc = $timestamp.ToString('o')
        status = $status
        profile_path = $profileResolved
        workspace_root = $workspaceResolved
        artifact_report = $reportPath
        source_aligned_count = $sourceAlignedFiles.Count
        destination_aligned_count = $destinationAlignedFiles.Count
        parameters = $report.parameters
        safety = $report.safety
    }
    [System.IO.File]::WriteAllText($workspaceExtractionManifest, ($workspaceReport | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($true))
}

[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 14), [System.Text.UTF8Encoding]::new($true))

Write-Host ''
Write-Host '[3/4] Controlled face extraction result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Source role: {0}; aligned files: {1}" -f $(if ($null -eq $sourceResult) { 'not-run' } else { $sourceResult.status }), $sourceAlignedFiles.Count)
Write-Host ("Destination role: {0}; aligned files: {1}" -f $(if ($null -eq $destinationResult) { 'not-run' } else { $destinationResult.status }), $destinationAlignedFiles.Count)
Write-Host ("Input hashes unchanged: {0}" -f $inputsUnchanged)
Write-Host ("Historical default workspace unchanged: {0}" -f $defaultWorkspaceUnchanged)
Write-Host ("Repository unchanged: {0}" -f $repoUnchanged)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ''
Write-Host '[4/4] Safety boundary' -ForegroundColor Cyan
Write-Host 'Face detection and alignment were the only DeepFaceLab workflow actions. No model, training, merge, or export was started.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    source_status = $(if ($null -eq $sourceResult) { 'not-run' } else { $sourceResult.status })
    destination_status = $(if ($null -eq $destinationResult) { 'not-run' } else { $destinationResult.status })
    source_aligned_count = $sourceAlignedFiles.Count
    destination_aligned_count = $destinationAlignedFiles.Count
    inputs_unchanged = $inputsUnchanged
    historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
    repository_unchanged = $repoUnchanged
}

if ($status -ne 'passed') { exit 1 }
exit 0
