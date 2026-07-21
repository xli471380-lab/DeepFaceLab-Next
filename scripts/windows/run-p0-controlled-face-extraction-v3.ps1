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
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Get-ProfileValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not $profile.ContainsKey($Name)) {
        throw "Missing profile key: $Name"
    }

    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Empty profile value: $Name"
    }

    return $value
}

function Get-PropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
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

    if ($candidateFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

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
        $kind = 'F'
        $length = [int64]$item.Length

        if ($item.PSIsContainer) {
            $kind = 'D'
            $length = [int64]0
        }

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
    foreach ($file in $files) {
        $totalBytes += [int64]$file.Length
    }

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

    if ($null -eq $Text) {
        return ''
    }

    if ($Text.Length -le $MaximumCharacters) {
        return $Text
    }

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
        if (-not $started) {
            throw ("Process did not start: {0}" -f $Label)
        }

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

        try {
            $process.WaitForExit()
        }
        catch {}

        try {
            $stdout = [string]$stdoutTask.Result
        }
        catch {
            $stdout = ''
        }

        try {
            $stderr = [string]$stderrTask.Result
        }
        catch {
            $stderr = $_.Exception.ToString()
        }

        if (-not $timedOut) {
            try {
                $exitCode = [int]$process.ExitCode
            }
            catch {
                $exitCode = $null
            }
        }
    }
    catch {
        $stderr = $_.Exception.ToString()
    }
    finally {
        if ($started) {
            try {
                $process.Refresh()
                if (-not $process.HasExited) {
                    Stop-ProcessTree -ProcessId $process.Id
                }
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

    $pattern = '(?s)__DFLNEXT_FACESET_VALIDATION_JSON_BEGIN__\s*(.*?)\s*__DFLNEXT_FACESET_VALIDATION_JSON_END__'
    $match = [regex]::Match($Text, $pattern)

    if (-not $match.Success) {
        return [ordered]@{
            value = $null
            error = 'Faceset validation sentinel JSON markers were not found.'
        }
    }

    try {
        $value = $match.Groups[1].Value | ConvertFrom-Json
        return [ordered]@{
            value = $value
            error = $null
        }
    }
    catch {
        return [ordered]@{
            value = $null
            error = $_.Exception.Message
        }
    }
}

function Confirm-CopiedInputs {
    param(
        [Parameter(Mandatory = $true)]$Records,
        [Parameter(Mandatory = $true)][string]$Role
    )

    $verified = New-Object System.Collections.ArrayList

    foreach ($record in @($Records)) {
        $relative = [string](Get-PropertyValue -Object $record -Name 'target_relative_path' -Default '')
        $expectedHash = [string](Get-PropertyValue -Object $record -Name 'sha256' -Default '')
        $path = Join-Path $workspaceResolved $relative

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ("Missing isolated workspace input for {0}: {1}" -f $Role, $path)
        }

        $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actualHash -ne $expectedHash) {
            throw ("Isolated workspace input hash mismatch for {0}: {1}" -f $Role, $path)
        }

        [void]$verified.Add([ordered]@{
            role = $Role
            path = $path
            name = Split-Path -Leaf $path
            sha256 = $actualHash
            size_bytes = [int64](Get-Item -LiteralPath $path -Force).Length
        })
    }

    return @($verified | ForEach-Object { $_ })
}

function Confirm-InputsUnchanged {
    param([Parameter(Mandatory = $true)]$VerifiedRecords)

    foreach ($record in @($VerifiedRecords)) {
        if (-not (Test-Path -LiteralPath $record.path -PathType Leaf)) {
            return $false
        }

        $actualHash = (Get-FileHash -LiteralPath $record.path -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actualHash -ne [string]$record.sha256) {
            return $false
        }
    }

    return $true
}

function Get-InputMediaFiles {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $allowed = @('.jpg', '.jpeg', '.png', '.webp', '.bmp', '.tif', '.tiff')
    return @(
        Get-ChildItem -LiteralPath $Directory -File -Force -ErrorAction Stop |
            Where-Object { $allowed -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object Name
    )
}

function Invoke-RoleExtraction {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$InputDirectory,
        [Parameter(Mandatory = $true)][string]$StagingDirectory,
        [Parameter(Mandatory = $true)][string]$LogPrefix,
        [Parameter(Mandatory = $true)][int]$ExpectedInputCount
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

    $extractProcess = Invoke-IsolatedProcess -Label ($Role + '-extract') -Arguments $extractArguments -TimeoutSeconds $TimeoutSecondsPerRole
    $extractStdoutPath = Join-Path $outputDirectory ($LogPrefix + '.extract.stdout.txt')
    $extractStderrPath = Join-Path $outputDirectory ($LogPrefix + '.extract.stderr.txt')
    [System.IO.File]::WriteAllText($extractStdoutPath, [string]$extractProcess.stdout, $utf8Bom)
    [System.IO.File]::WriteAllText($extractStderrPath, [string]$extractProcess.stderr, $utf8Bom)

    $validatorProcess = $null
    $validatorParse = [ordered]@{
        value = $null
        error = 'Validator was not run because extraction did not complete successfully.'
    }
    $validatorStdoutPath = Join-Path $outputDirectory ($LogPrefix + '.validate.stdout.txt')
    $validatorStderrPath = Join-Path $outputDirectory ($LogPrefix + '.validate.stderr.txt')

    $extractCompleted = $false
    if (-not $extractProcess.timed_out) {
        if ($null -ne $extractProcess.exit_code) {
            if ([int]$extractProcess.exit_code -eq 0) {
                $extractCompleted = $true
            }
        }
    }

    if ($extractCompleted) {
        Write-Host ("  [{0}] validating DFLJPG metadata and source mapping..." -f $Role) -ForegroundColor Cyan
        $validatorArguments = @($validatorScript, $deepFaceLabRoot, $InputDirectory, $StagingDirectory)
        $validatorProcess = Invoke-IsolatedProcess -Label ($Role + '-validate') -Arguments $validatorArguments -TimeoutSeconds 60
        [System.IO.File]::WriteAllText($validatorStdoutPath, [string]$validatorProcess.stdout, $utf8Bom)
        [System.IO.File]::WriteAllText($validatorStderrPath, [string]$validatorProcess.stderr, $utf8Bom)
        $validatorParse = Convert-ValidationResult -Text ([string]$validatorProcess.stdout)
    }
    else {
        [System.IO.File]::WriteAllText($validatorStdoutPath, '', $utf8Bom)
        [System.IO.File]::WriteAllText($validatorStderrPath, '', $utf8Bom)
    }

    $validatorStatus = ''
    $validatedAlignedCount = 0
    $validatedInputCount = 0

    if ($null -ne $validatorParse.value) {
        $validatorStatus = [string](Get-PropertyValue -Object $validatorParse.value -Name 'status' -Default '')
        $validatedAlignedCount = [int](Get-PropertyValue -Object $validatorParse.value -Name 'aligned_count' -Default 0)
        $validatedInputCount = [int](Get-PropertyValue -Object $validatorParse.value -Name 'input_count' -Default 0)
    }

    $validatorCompleted = $false
    if ($null -ne $validatorProcess) {
        if (-not $validatorProcess.timed_out) {
            if ($null -ne $validatorProcess.exit_code) {
                if ([int]$validatorProcess.exit_code -eq 0) {
                    $validatorCompleted = $true
                }
            }
        }
    }

    $passed = $false
    if ($extractCompleted -and $validatorCompleted) {
        if ($null -eq $validatorParse.error) {
            if ($validatorStatus -eq 'passed') {
                if ($validatedInputCount -eq $ExpectedInputCount) {
                    if ($validatedAlignedCount -eq $ExpectedInputCount) {
                        $passed = $true
                    }
                }
            }
        }
    }

    $imagesFound = $null
    $facesDetected = $null
    $imagesMatch = [regex]::Matches([string]$extractProcess.stdout, 'Images found:\s*(\d+)')
    if ($imagesMatch.Count -gt 0) {
        $imagesFound = [int]$imagesMatch[$imagesMatch.Count - 1].Groups[1].Value
    }

    $facesMatch = [regex]::Matches([string]$extractProcess.stdout, 'Faces detected:\s*(\d+)')
    if ($facesMatch.Count -gt 0) {
        $facesDetected = [int]$facesMatch[$facesMatch.Count - 1].Groups[1].Value
    }

    $roleStatus = 'blocked_extraction_or_validation'
    if ($passed) {
        $roleStatus = 'passed'
    }
    elseif ($extractProcess.timed_out) {
        $roleStatus = 'blocked_timeout'
    }
    elseif ($null -ne $validatorParse.error) {
        $roleStatus = 'blocked_invalid_validation_output'
    }

    $validatorTimedOut = $false
    $validatorExitCode = $null
    $validatorStderrTail = ''

    if ($null -ne $validatorProcess) {
        $validatorTimedOut = [bool]$validatorProcess.timed_out
        $validatorExitCode = $validatorProcess.exit_code
        $validatorStderrTail = Limit-Text -Text ([string]$validatorProcess.stderr)
    }

    return [ordered]@{
        role = $Role
        status = $roleStatus
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
            timed_out = $validatorTimedOut
            exit_code = $validatorExitCode
            parse_error = $validatorParse.error
            result = $validatorParse.value
            stdout_file = $validatorStdoutPath
            stderr_file = $validatorStderrPath
            stderr_tail = $validatorStderrTail
        }
    }
}

if (-not $ExtractConfirmed) {
    throw 'Controlled extraction confirmation was not supplied. Use the step-13 BAT and confirm the bounded synthetic-data extraction.'
}

if (-not (Test-Path -LiteralPath $validatorScript -PathType Leaf)) {
    throw "Aligned faces validator was not found: $validatorScript"
}

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
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path does not exist: $requiredPath"
    }
}

if (Test-PathInside -Candidate $workspaceResolved -Parent $repoRootNormalized) {
    throw 'The isolated P0 workspace must stay outside the Git repository.'
}

if (Test-PathInside -Candidate $workspaceResolved -Parent $runtimeRoot) {
    throw 'The isolated P0 workspace must stay outside the historical runtime.'
}

$workspaceMarkerPath = Join-Path $workspaceResolved 'p0-workspace-manifest.json'
if (-not (Test-Path -LiteralPath $workspaceMarkerPath -PathType Leaf)) {
    throw "P0 workspace marker was not found: $workspaceMarkerPath"
}

$workspaceMarker = Get-Content -LiteralPath $workspaceMarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
$markerProfile = [System.IO.Path]::GetFullPath([string](Get-PropertyValue -Object $workspaceMarker -Name 'profile_path' -Default ''))
$markerWorkspace = [System.IO.Path]::GetFullPath([string](Get-PropertyValue -Object $workspaceMarker -Name 'workspace_root' -Default ''))

if ($markerProfile -ne [System.IO.Path]::GetFullPath($profileResolved)) {
    throw 'The isolated workspace belongs to a different local profile.'
}

if ($markerWorkspace -ne [System.IO.Path]::GetFullPath($workspaceResolved)) {
    throw 'The workspace marker root does not match the requested workspace.'
}

$artifactRoot = Join-Path $repoRoot ("artifacts\p0\{0}\{1}" -f $machineId, $environmentId)
$workspacePreparationDirectory = Join-Path $artifactRoot 'workspace-preparation'
$workspacePreparationReport = Get-ChildItem -LiteralPath $workspacePreparationDirectory -Filter 'p0-isolated-workspace-preparation-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $workspacePreparationReport) {
    throw 'A passed step-12 workspace preparation report is required.'
}

$step12 = Get-Content -LiteralPath $workspacePreparationReport.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
$step12Status = [string](Get-PropertyValue -Object $step12 -Name 'status' -Default '')
$step12Workspace = Get-PropertyValue -Object $step12 -Name 'workspace' -Default $null
$step12WorkspaceRoot = [string](Get-PropertyValue -Object $step12Workspace -Name 'isolated_root' -Default '')

if ($step12Status -ne 'passed') {
    throw 'The latest step-12 report is not passed.'
}

if ([System.IO.Path]::GetFullPath($step12WorkspaceRoot) -ne [System.IO.Path]::GetFullPath($workspaceResolved)) {
    throw 'The latest step-12 report belongs to a different isolated workspace.'
}

$gpuProbeDirectory = Join-Path $artifactRoot 'tensorflow-gpu-probe'
$gpuReport = Get-ChildItem -LiteralPath $gpuProbeDirectory -Filter 'legacy-tensorflow-gpu-visibility-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $gpuReport) {
    throw 'A passed step-10 TensorFlow/GPU visibility report is required.'
}

$step10 = Get-Content -LiteralPath $gpuReport.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
$step10Status = [string](Get-PropertyValue -Object $step10 -Name 'status' -Default '')
$step10Profile = [string](Get-PropertyValue -Object $step10 -Name 'profile_path' -Default '')

if ($step10Status -ne 'passed') {
    throw 'The latest step-10 TensorFlow/GPU visibility report is not passed.'
}

if ([System.IO.Path]::GetFullPath($step10Profile) -ne [System.IO.Path]::GetFullPath($profileResolved)) {
    throw 'The latest step-10 report belongs to a different local profile.'
}

$sourceInput = Join-Path $workspaceResolved 'data_src'
$destinationInput = Join-Path $workspaceResolved 'data_dst'
$sourceAligned = Join-Path $sourceInput 'aligned'
$destinationAligned = Join-Path $destinationInput 'aligned'

foreach ($directory in @($sourceInput, $destinationInput, $sourceAligned, $destinationAligned)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Required workspace directory is missing: $directory"
    }
}

foreach ($alignedDirectory in @($sourceAligned, $destinationAligned)) {
    $alignedItems = @(Get-ChildItem -LiteralPath $alignedDirectory -Force -ErrorAction Stop)
    if ($alignedItems.Count -ne 0) {
        throw "Aligned output directory must be empty before step 13; nothing will be deleted: $alignedDirectory"
    }
}

$copiedFiles = @(Get-PropertyValue -Object $workspaceMarker -Name 'copied_files' -Default @())
$sourceMarkerRecords = @($copiedFiles | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'role' -Default '') -eq 'source' })
$destinationMarkerRecords = @($copiedFiles | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'role' -Default '') -eq 'destination' })

if (($sourceMarkerRecords.Count -eq 0) -or ($destinationMarkerRecords.Count -eq 0)) {
    throw 'Workspace marker contains no copied source or destination files.'
}

$verifiedSourceInputs = Confirm-CopiedInputs -Records $sourceMarkerRecords -Role 'source'
$verifiedDestinationInputs = Confirm-CopiedInputs -Records $destinationMarkerRecords -Role 'destination'
$sourceMediaFiles = Get-InputMediaFiles -Directory $sourceInput
$destinationMediaFiles = Get-InputMediaFiles -Directory $destinationInput

if ($sourceMediaFiles.Count -ne $verifiedSourceInputs.Count) {
    throw 'Source input directory contains unmanifested media files.'
}

if ($destinationMediaFiles.Count -ne $verifiedDestinationInputs.Count) {
    throw 'Destination input directory contains unmanifested media files.'
}

$unexpectedStaging = @(
    Get-ChildItem -LiteralPath $sourceInput -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.aligned-p0-staging-*' }
    Get-ChildItem -LiteralPath $destinationInput -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.aligned-p0-staging-*' }
)

if ($unexpectedStaging.Count -gt 0) {
    throw 'A previous staging directory exists. Inspect it manually before retrying; nothing was deleted.'
}

$repoStatusBefore = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
if (-not [string]::IsNullOrWhiteSpace($repoStatusBefore)) {
    throw 'The Git working tree is not clean.'
}

$defaultWorkspaceBefore = Get-TreeSnapshot -Path $defaultWorkspace
$internalRoot = Join-Path $runtimeRoot '_internal'
$pythonRoot = Split-Path -Parent $pythonExe
$dllPatterns = @(
    'cudart64*.dll',
    'cudnn64*.dll',
    'cublas64*.dll',
    'cublasLt64*.dll',
    'cufft64*.dll',
    'curand64*.dll',
    'cusolver64*.dll',
    'cusparse64*.dll',
    'nvrtc64*.dll',
    'nvrtc-builtins64*.dll',
    'zlibwapi.dll'
)

$dllFilesList = New-Object System.Collections.ArrayList
foreach ($pattern in $dllPatterns) {
    $matches = @(Get-ChildItem -LiteralPath $internalRoot -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($file in $matches) {
        [void]$dllFilesList.Add($file)
    }
}

$dllFiles = @($dllFilesList | Sort-Object FullName -Unique)
$dllDirectories = @($dllFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
$candidatePaths = @($pythonRoot, (Join-Path $pythonRoot 'Scripts'), $internalRoot) + @($dllDirectories) + @((Join-Path $env:SystemRoot 'System32'), $env:SystemRoot)
$pathEntriesList = New-Object System.Collections.ArrayList

foreach ($candidate in $candidatePaths) {
    $candidateExists = $false
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        $candidateExists = Test-Path -LiteralPath $candidate
    }

    if ($candidateExists -and (-not $pathEntriesList.Contains($candidate))) {
        [void]$pathEntriesList.Add($candidate)
    }
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
$fatalError = $null

try {
    $sourceResult = Invoke-RoleExtraction -Role 'source' -InputDirectory $sourceInput -StagingDirectory $sourceStaging -LogPrefix ($fileTimestamp + '-source') -ExpectedInputCount $verifiedSourceInputs.Count

    if ([string]$sourceResult.status -eq 'passed') {
        $destinationResult = Invoke-RoleExtraction -Role 'destination' -InputDirectory $destinationInput -StagingDirectory $destinationStaging -LogPrefix ($fileTimestamp + '-destination') -ExpectedInputCount $verifiedDestinationInputs.Count
    }

    $sourceInputsUnchanged = Confirm-InputsUnchanged -VerifiedRecords $verifiedSourceInputs
    $destinationInputsUnchanged = Confirm-InputsUnchanged -VerifiedRecords $verifiedDestinationInputs
    $inputsUnchanged = $sourceInputsUnchanged -and $destinationInputsUnchanged

    $defaultWorkspaceAfterExtraction = Get-TreeSnapshot -Path $defaultWorkspace
    $defaultWorkspaceUnchanged = $defaultWorkspaceBefore.metadata_sha256 -eq $defaultWorkspaceAfterExtraction.metadata_sha256
    $repoStatusAfterExtraction = (& git -C $repoRoot status --porcelain=v1 2>$null | Out-String).Trim()
    $repoUnchanged = $repoStatusBefore -eq $repoStatusAfterExtraction

    if ([string]$sourceResult.status -ne 'passed') {
        $status = 'blocked_source_extraction'
    }
    elseif ($null -eq $destinationResult) {
        $status = 'blocked_destination_not_run'
    }
    elseif ([string]$destinationResult.status -ne 'passed') {
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
        $sourceAlignedItems = @(Get-ChildItem -LiteralPath $sourceAligned -Force -ErrorAction Stop)
        $destinationAlignedItems = @(Get-ChildItem -LiteralPath $destinationAligned -Force -ErrorAction Stop)

        if (($sourceAlignedItems.Count -ne 0) -or ($destinationAlignedItems.Count -ne 0)) {
            $status = 'blocked_aligned_changed_before_commit'
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
                if ((Test-Path -LiteralPath $sourceAligned) -and (-not (Test-Path -LiteralPath $sourceStaging))) {
                    Move-Item -LiteralPath $sourceAligned -Destination $sourceStaging -ErrorAction SilentlyContinue
                }

                if ((Test-Path -LiteralPath $destinationAligned) -and (-not (Test-Path -LiteralPath $destinationStaging))) {
                    Move-Item -LiteralPath $destinationAligned -Destination $destinationStaging -ErrorAction SilentlyContinue
                }

                if (-not (Test-Path -LiteralPath $sourceAligned)) {
                    New-Item -ItemType Directory -Path $sourceAligned -Force | Out-Null
                }

                if (-not (Test-Path -LiteralPath $destinationAligned)) {
                    New-Item -ItemType Directory -Path $destinationAligned -Force | Out-Null
                }

                $status = 'blocked_output_commit_failed'
                $fatalError = $_.Exception.ToString()
            }
        }
    }
}
catch {
    $status = 'blocked_unhandled_exception'
    $fatalError = $_.Exception.ToString()
}
finally {
    if (-not $commitSucceeded) {
        foreach ($staging in @($sourceStaging, $destinationStaging)) {
            if (Test-Path -LiteralPath $staging) {
                Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$sourceAlignedFiles = @()
$destinationAlignedFiles = @()

if (Test-Path -LiteralPath $sourceAligned) {
    $sourceAlignedFiles = @(Get-ChildItem -LiteralPath $sourceAligned -Filter '*.jpg' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)
}

if (Test-Path -LiteralPath $destinationAligned) {
    $destinationAlignedFiles = @(Get-ChildItem -LiteralPath $destinationAligned -Filter '*.jpg' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)
}

$report = [ordered]@{
    schema_version = 2
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'p0_controlled_face_extraction'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    workspace_root = $workspaceResolved
    fatal_error = $fatalError
    preconditions = [ordered]@{
        step10_report = $gpuReport.FullName
        step10_status = $step10Status
        step12_report = $workspacePreparationReport.FullName
        step12_status = $step12Status
        workspace_marker = $workspaceMarkerPath
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
        preexisting_aligned_output_deleted = $false
    }
    source = $sourceResult
    destination = $destinationResult
    outputs = [ordered]@{
        commit_succeeded = $commitSucceeded
        source_aligned_dir = $sourceAligned
        destination_aligned_dir = $destinationAligned
        source_aligned_count = $sourceAlignedFiles.Count
        destination_aligned_count = $destinationAlignedFiles.Count
        source_files = @($sourceAlignedFiles | ForEach-Object {
            [ordered]@{
                name = $_.Name
                size_bytes = [int64]$_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
        destination_files = @($destinationAlignedFiles | ForEach-Object {
            [ordered]@{
                name = $_.Name
                size_bytes = [int64]$_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
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
    }
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

    [System.IO.File]::WriteAllText($workspaceExtractionManifest, ($workspaceReport | ConvertTo-Json -Depth 8), $utf8Bom)
}

[System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 14), $utf8Bom)

$sourceStatus = 'not-run'
$destinationStatus = 'not-run'

if ($null -ne $sourceResult) {
    $sourceStatus = [string]$sourceResult.status
}

if ($null -ne $destinationResult) {
    $destinationStatus = [string]$destinationResult.status
}

Write-Host ''
Write-Host '[3/4] Controlled face extraction result' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Source role: {0}; aligned files: {1}" -f $sourceStatus, $sourceAlignedFiles.Count)
Write-Host ("Destination role: {0}; aligned files: {1}" -f $destinationStatus, $destinationAlignedFiles.Count)
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
    source_status = $sourceStatus
    destination_status = $destinationStatus
    source_aligned_count = $sourceAlignedFiles.Count
    destination_aligned_count = $destinationAlignedFiles.Count
    inputs_unchanged = $inputsUnchanged
    historical_default_workspace_unchanged = $defaultWorkspaceUnchanged
    repository_unchanged = $repoUnchanged
}

if ($status -ne 'passed') {
    exit 1
}

exit 0
