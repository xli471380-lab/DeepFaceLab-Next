[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string[]]$SearchRoots,
    [int]$MaxDepth = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$machineId = $env:COMPUTERNAME.ToLowerInvariant()
$environmentId = 'runtime-discovery'

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

if ($MaxDepth -lt 1 -or $MaxDepth -gt 8) {
    throw 'MaxDepth must be between 1 and 8.'
}

if ($null -eq $SearchRoots -or $SearchRoots.Count -eq 0) {
    $SearchRoots = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { $_.DeviceID + '\' })
}

$validRoots = @()
foreach ($root in $SearchRoots) {
    if (Test-Path -LiteralPath $root -PathType Container) {
        $validRoots += (Resolve-Path -LiteralPath $root).Path
    }
}
if ($validRoots.Count -eq 0) {
    throw 'No valid search roots were found.'
}

$skipNames = @(
    '$Recycle.Bin',
    'System Volume Information',
    'Windows',
    'ProgramData',
    'Recovery',
    'node_modules',
    '.git',
    'artifacts',
    'workspace'
)

function Test-SkippedDirectory {
    param([System.IO.DirectoryInfo]$Directory)
    return $skipNames -contains $Directory.Name
}

function Get-ChildDirectoriesSafe {
    param([string]$Path)
    try {
        return @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Get-FileMatches {
    param(
        [string]$Path,
        [string[]]$RelativeCandidates
    )
    $matches = @()
    foreach ($relative in $RelativeCandidates) {
        $candidate = Join-Path $Path $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $matches += (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $matches
}

function Get-PythonVersionSafe {
    param([string]$PythonPath)
    if ([string]::IsNullOrWhiteSpace($PythonPath) -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        return $null
    }
    try {
        $output = & $PythonPath --version 2>&1 | ForEach-Object { $_.ToString() }
        return ($output -join ' ').Trim()
    }
    catch {
        return $_.Exception.Message
    }
}

$candidatePattern = '(?i)(deep[ _.-]*face[ _.-]*lab|deepfacelab|^dfl($|[ _.-]))'
$queue = New-Object System.Collections.Queue
foreach ($root in $validRoots) {
    $queue.Enqueue([PSCustomObject]@{ Path = $root; Depth = 0 })
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$candidatePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

while ($queue.Count -gt 0) {
    $item = $queue.Dequeue()
    if (-not $seen.Add($item.Path)) { continue }

    $directoryInfo = Get-Item -LiteralPath $item.Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $directoryInfo) { continue }

    if ($directoryInfo.Name -match $candidatePattern) {
        [void]$candidatePaths.Add($directoryInfo.FullName)
    }

    if ($item.Depth -ge $MaxDepth) { continue }

    foreach ($child in (Get-ChildDirectoriesSafe -Path $item.Path)) {
        if (Test-SkippedDirectory -Directory $child) { continue }
        $queue.Enqueue([PSCustomObject]@{ Path = $child.FullName; Depth = $item.Depth + 1 })
    }
}

$results = @()
foreach ($candidatePath in @($candidatePaths | Sort-Object)) {
    $pythonMatches = Get-FileMatches -Path $candidatePath -RelativeCandidates @(
        '_internal\python-3.6.8\python.exe',
        '_internal\python-3.7.6\python.exe',
        '_internal\python\python.exe',
        'python_embeded\python.exe',
        'python\python.exe',
        'python.exe'
    )
    $ffmpegMatches = Get-FileMatches -Path $candidatePath -RelativeCandidates @(
        '_internal\ffmpeg.exe',
        '_internal\ffmpeg\ffmpeg.exe',
        'ffmpeg\bin\ffmpeg.exe',
        'ffmpeg.exe'
    )
    $markerMatches = @()
    foreach ($marker in @('main.py','requirements-cuda.txt','workspace','_internal')) {
        $markerPath = Join-Path $candidatePath $marker
        if (Test-Path -LiteralPath $markerPath) {
            $markerMatches += (Resolve-Path -LiteralPath $markerPath).Path
        }
    }
    $batchFiles = @()
    try {
        $batchFiles = @(Get-ChildItem -LiteralPath $candidatePath -Filter '*.bat' -File -ErrorAction Stop | Select-Object -ExpandProperty FullName)
    }
    catch {
        $batchFiles = @()
    }

    $score = 0
    if ($candidatePath -match $candidatePattern) { $score += 2 }
    if ($pythonMatches.Count -gt 0) { $score += 3 }
    if ($ffmpegMatches.Count -gt 0) { $score += 2 }
    if ($markerMatches.Count -gt 0) { $score += $markerMatches.Count }
    if ($batchFiles.Count -ge 3) { $score += 2 }

    $pythonDetails = @()
    foreach ($pythonPath in $pythonMatches) {
        $pythonDetails += [PSCustomObject]@{
            path = $pythonPath
            version = Get-PythonVersionSafe -PythonPath $pythonPath
        }
    }

    $results += [PSCustomObject]@{
        path = $candidatePath
        score = $score
        likely_legacy_bundle = ($score -ge 6)
        python = $pythonDetails
        ffmpeg = $ffmpegMatches
        markers = $markerMatches
        batch_files = $batchFiles
    }
}

$timestamp = (Get-Date).ToUniversalTime()
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\runtime-discovery" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputPath = Join-Path $outputDirectory ("legacy-runtime-discovery-{0}.json" -f $timestamp.ToString('yyyyMMddTHHmmssZ'))

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    machine_id = $machineId
    environment_id = $environmentId
    search_roots = $validRoots
    max_depth = $MaxDepth
    candidate_count = @($results).Count
    likely_bundle_count = @($results | Where-Object { $_.likely_legacy_bundle }).Count
    candidates = @($results | Sort-Object score -Descending, path)
    safety_note = 'The scan only reads directory metadata and runs python.exe --version for discovered embedded interpreters. It does not run BAT files or install software.'
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8

Write-Host ''
Write-Host 'DeepFaceLab historical runtime discovery completed.' -ForegroundColor Green
Write-Host ("Search roots: {0}" -f ($validRoots -join ', '))
Write-Host ("Candidates: {0}" -f $report.candidate_count)
Write-Host ("Likely bundles: {0}" -f $report.likely_bundle_count)
Write-Host ("Report: {0}" -f $outputPath)

if ($report.likely_bundle_count -gt 0) {
    Write-Host ''
    Write-Host 'Likely reusable bundles:' -ForegroundColor Cyan
    $results | Where-Object { $_.likely_legacy_bundle } | Sort-Object score -Descending | ForEach-Object {
        Write-Host ("- [{0}] {1}" -f $_.score, $_.path)
    }
}
else {
    Write-Host ''
    Write-Host 'No reusable historical bundle was confirmed by this scan.' -ForegroundColor Yellow
}

[PSCustomObject]@{
    report_path = $outputPath
    candidate_count = $report.candidate_count
    likely_bundle_count = $report.likely_bundle_count
}
