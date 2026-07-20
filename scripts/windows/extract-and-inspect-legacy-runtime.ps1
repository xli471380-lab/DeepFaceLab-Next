[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [string]$ProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$package = Get-Item -LiteralPath $resolvedPackage -Force

if ($package.PSIsContainer -or $package.Extension -ine '.exe') {
    throw 'PackagePath must point to the downloaded 7-Zip SFX EXE.'
}

$sevenZipCandidates = @(
    (Get-Command '7z.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe' } else { $null })
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique

$sevenZip = $sevenZipCandidates | Select-Object -First 1
if (-not $sevenZip) {
    throw '7-Zip was not found.'
}

$actualHash = (Get-FileHash -LiteralPath $resolvedPackage -Algorithm SHA256).Hash.ToUpperInvariant()
$expectedHash = $ExpectedSha256.Trim().ToUpperInvariant()
if ($actualHash -ne $expectedHash) {
    throw "SHA-256 mismatch. Expected $expectedHash but found $actualHash."
}

$destinationFull = [System.IO.Path]::GetFullPath($DestinationPath)
if ($destinationFull.TrimEnd('\') -ieq $repoRoot.TrimEnd('\')) {
    throw 'DestinationPath must be outside the source repository.'
}
if ($destinationFull.StartsWith($repoRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'DestinationPath must be outside the source repository.'
}

if (Test-Path -LiteralPath $destinationFull) {
    $existing = @(Get-ChildItem -LiteralPath $destinationFull -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        throw "Destination already exists and is not empty: $destinationFull"
    }
}
else {
    New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
}

$machineId = $env:COMPUTERNAME.ToLowerInvariant()
$environmentId = 'legacy-runtime-extraction'
if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
    $resolvedProfile = (Resolve-Path -LiteralPath $ProfilePath).Path
    $profile = Import-PowerShellDataFile -LiteralPath $resolvedProfile
    if ($profile.ContainsKey('MachineId') -and -not [string]::IsNullOrWhiteSpace([string]$profile.MachineId)) {
        $machineId = [string]$profile.MachineId
    }
    if ($profile.ContainsKey('EnvironmentId') -and -not [string]::IsNullOrWhiteSpace([string]$profile.EnvironmentId)) {
        $environmentId = [string]$profile.EnvironmentId
    }
}

$timestamp = (Get-Date).ToUniversalTime()
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\legacy-runtime-extraction" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$reportPath = Join-Path $outputDirectory ("legacy-runtime-extraction-{0}.json" -f $fileTimestamp)
$listPath = Join-Path $outputDirectory ("legacy-runtime-archive-list-{0}.txt" -f $fileTimestamp)
$extractLogPath = Join-Path $outputDirectory ("legacy-runtime-extract-{0}.txt" -f $fileTimestamp)

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        return [ordered]@{
            exit_code = $LASTEXITCODE
            output = ($lines -join [Environment]::NewLine).Trim()
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Get-SevenZipEntryPaths {
    param([Parameter(Mandatory = $true)][string]$ListingText)

    # 7-Zip -slt prints one or more archive-metadata records before the
    # actual file records. The first metadata Path is the absolute path of
    # the SFX being inspected and must not be treated as an archive entry.
    # Real entry records contain an exact "Size =" or "Attributes =" field.
    $entryPaths = New-Object System.Collections.ArrayList
    $currentPath = $null
    $currentIsEntry = $false

    foreach ($line in @($ListingText -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($null -ne $currentPath -and $currentIsEntry) {
                [void]$entryPaths.Add($currentPath)
            }
            $currentPath = $null
            $currentIsEntry = $false
            continue
        }

        if ($line -like 'Path = *') {
            if ($null -ne $currentPath -and $currentIsEntry) {
                [void]$entryPaths.Add($currentPath)
            }
            $currentPath = $line.Substring(7)
            $currentIsEntry = $false
            continue
        }

        if ($line -like 'Size = *' -or $line -like 'Attributes = *' -or $line -like 'Folder = *') {
            $currentIsEntry = $true
        }
    }

    if ($null -ne $currentPath -and $currentIsEntry) {
        [void]$entryPaths.Add($currentPath)
    }

    return @($entryPaths)
}

$listResult = Invoke-NativeCapture -Executable $sevenZip -Arguments @('l', '-slt', $resolvedPackage)
$listResult.output | Set-Content -LiteralPath $listPath -Encoding UTF8
if ($listResult.exit_code -ne 0) {
    throw "7-Zip listing failed with exit code $($listResult.exit_code)."
}

$allPathValues = @($listResult.output -split "`r?`n" | Where-Object { $_ -like 'Path = *' } | ForEach-Object { $_.Substring(7) })
$archivePaths = @(Get-SevenZipEntryPaths -ListingText $listResult.output)
if ($archivePaths.Count -eq 0) {
    throw '7-Zip listing did not yield any archive entry records.'
}

$unsafePaths = @($archivePaths | Where-Object {
    $_ -match '(^|[\\/])\.\.([\\/]|$)' -or
    $_ -match '^[A-Za-z]:' -or
    $_ -match '^[\\/]{2}' -or
    $_ -match '^[\\/]' -or
    $_ -match ':'
})
if ($unsafePaths.Count -gt 0) {
    throw ('Archive contains unsafe absolute, parent-traversal, or alternate-stream paths: ' + (($unsafePaths | Select-Object -First 10) -join '; '))
}

$testResult = Invoke-NativeCapture -Executable $sevenZip -Arguments @('t', $resolvedPackage)
if ($testResult.exit_code -ne 0) {
    throw "7-Zip integrity test failed with exit code $($testResult.exit_code)."
}

$extractResult = Invoke-NativeCapture -Executable $sevenZip -Arguments @('x', $resolvedPackage, ("-o{0}" -f $destinationFull), '-y', '-bb1')
$extractResult.output | Set-Content -LiteralPath $extractLogPath -Encoding UTF8
if ($extractResult.exit_code -ne 0) {
    throw "7-Zip extraction failed with exit code $($extractResult.exit_code)."
}

$files = @(Get-ChildItem -LiteralPath $destinationFull -File -Recurse -Force -ErrorAction Stop)
$directories = @(Get-ChildItem -LiteralPath $destinationFull -Directory -Recurse -Force -ErrorAction Stop)
$topLevel = @(Get-ChildItem -LiteralPath $destinationFull -Force | Select-Object Name, FullName, PSIsContainer)

$pythonCandidates = @($files | Where-Object { $_.Name -ieq 'python.exe' } | Select-Object -ExpandProperty FullName)
$ffmpegCandidates = @($files | Where-Object { $_.Name -ieq 'ffmpeg.exe' } | Select-Object -ExpandProperty FullName)
$batCandidates = @($files | Where-Object { $_.Extension -ieq '.bat' } | Select-Object -ExpandProperty FullName)
$workspaceCandidates = @($directories | Where-Object { $_.Name -ieq 'workspace' } | Select-Object -ExpandProperty FullName)
$internalCandidates = @($directories | Where-Object { $_.Name -ieq '_internal' } | Select-Object -ExpandProperty FullName)
$mainCandidates = @($files | Where-Object { $_.Name -ieq 'main.py' } | Select-Object -ExpandProperty FullName)

$report = [ordered]@{
    schema_version = 2
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    machine_id = $machineId
    environment_id = $environmentId
    package = [ordered]@{
        path = $resolvedPackage
        size_bytes = [int64]$package.Length
        sha256 = $actualHash
        expected_sha256 = $expectedHash
        hash_match = ($actualHash -eq $expectedHash)
    }
    seven_zip = [ordered]@{
        path = $sevenZip
        list_exit_code = $listResult.exit_code
        test_exit_code = $testResult.exit_code
        extraction_exit_code = $extractResult.exit_code
        raw_path_value_count = $allPathValues.Count
        metadata_path_value_count = ($allPathValues.Count - $archivePaths.Count)
        listed_entry_count = $archivePaths.Count
        unsafe_path_count = $unsafePaths.Count
        list_output_file = $listPath
        extraction_output_file = $extractLogPath
    }
    destination = [ordered]@{
        path = $destinationFull
        top_level = @($topLevel)
        file_count = $files.Count
        directory_count = $directories.Count
        total_size_bytes = [int64](($files | Measure-Object Length -Sum).Sum)
        bat_count = @($files | Where-Object { $_.Extension -ieq '.bat' }).Count
        exe_count = @($files | Where-Object { $_.Extension -ieq '.exe' }).Count
        dll_count = @($files | Where-Object { $_.Extension -ieq '.dll' }).Count
        py_count = @($files | Where-Object { $_.Extension -ieq '.py' }).Count
        python_candidates = @($pythonCandidates)
        ffmpeg_candidates = @($ffmpegCandidates)
        main_py_candidates = @($mainCandidates)
        workspace_candidates = @($workspaceCandidates)
        internal_candidates = @($internalCandidates)
        bat_samples = @($batCandidates | Select-Object -First 50)
    }
    next_action = 'Scan the extracted destination with the active antivirus provider before executing any included BAT, EXE, Python, or DLL.'
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Legacy runtime extraction completed without executing the SFX.' -ForegroundColor Green
Write-Host ("Destination: {0}" -f $destinationFull)
Write-Host ("SHA-256 verified: {0}" -f ($actualHash -eq $expectedHash))
Write-Host ("Archive integrity test: {0}" -f $testResult.exit_code)
Write-Host ("Archive entries checked: {0}" -f $archivePaths.Count)
Write-Host ("Files: {0}; Directories: {1}" -f $files.Count, $directories.Count)
Write-Host ("Embedded Python candidates: {0}" -f $pythonCandidates.Count)
Write-Host ("FFmpeg candidates: {0}" -f $ffmpegCandidates.Count)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ''
Write-Host 'Do not run any extracted file yet. Scan the destination with Huorong first.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    destination = $destinationFull
    hash_match = ($actualHash -eq $expectedHash)
    archive_test_exit_code = $testResult.exit_code
    extraction_exit_code = $extractResult.exit_code
    archive_entry_count = $archivePaths.Count
    file_count = $files.Count
    directory_count = $directories.Count
}
