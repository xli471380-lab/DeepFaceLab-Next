[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$profileResolved = (Resolve-Path -LiteralPath $ProfilePath).Path
$profile = Import-PowerShellDataFile -LiteralPath $profileResolved

function Read-ProfileValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Required = $true
    )

    if (-not $profile.ContainsKey($Name)) {
        if ($Required) { throw "Missing profile key: $Name" }
        return $null
    }

    $value = [string]$profile[$Name]
    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($Required) { throw "Empty profile value: $Name" }
        return $null
    }
    return $value
}

$machineId = Read-ProfileValue -Name 'MachineId'
$environmentId = Read-ProfileValue -Name 'EnvironmentId'
$runtimeRoot = Read-ProfileValue -Name 'RuntimeRoot'
$pythonExe = Read-ProfileValue -Name 'PythonExe'
$deepFaceLabRoot = Read-ProfileValue -Name 'DeepFaceLabRoot'
$mainPy = Read-ProfileValue -Name 'MainPy'
$workspacePath = Read-ProfileValue -Name 'WorkspacePath'

foreach ($path in @($runtimeRoot, $pythonExe, $deepFaceLabRoot, $mainPy, $workspacePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required profile path does not exist: $path"
    }
}

$pythonRoot = Split-Path -Parent $pythonExe
$sitePackages = Join-Path $pythonRoot 'Lib\site-packages'
if (-not (Test-Path -LiteralPath $sitePackages -PathType Container)) {
    throw "Embedded site-packages directory does not exist: $sitePackages"
}

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
    catch {
        return [ordered]@{
            exit_code = -1
            output = $_.Exception.ToString()
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Parse-SentinelJson {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [ordered]@{ value = $null; error = 'Python probe returned no output.' }
    }

    $match = [regex]::Match(
        $Text,
        '(?s)__DFL_JSON_BEGIN__\s*(.*?)\s*__DFL_JSON_END__'
    )
    if (-not $match.Success) {
        return [ordered]@{ value = $null; error = 'Sentinel JSON markers were not found in Python output.' }
    }

    try {
        return [ordered]@{ value = ($match.Groups[1].Value | ConvertFrom-Json); error = $null }
    }
    catch {
        return [ordered]@{ value = $null; error = $_.Exception.Message }
    }
}

function Get-RelativePathText {
    param([Parameter(Mandatory = $true)][string]$FullPath)
    return $FullPath.Substring($runtimeRoot.TrimEnd('\').Length).TrimStart('\')
}

function Read-TextRecord {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return [ordered]@{
            path = $Path
            exists = $true
            content = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
            error = $null
        }
    }
    catch {
        return [ordered]@{
            path = $Path
            exists = (Test-Path -LiteralPath $Path)
            content = $null
            error = $_.Exception.Message
        }
    }
}

function Find-StaticVersion {
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string[]]$CandidatePaths
    )

    foreach ($candidate in $CandidatePaths) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }

        try {
            $text = Get-Content -LiteralPath $candidate -Raw -ErrorAction Stop
            $patterns = @(
                '(?m)^\s*__version__\s*=\s*["'']([^"'']+)["'']',
                '(?m)^\s*version\s*=\s*["'']([^"'']+)["'']',
                '(?m)^\s*VERSION\s*=\s*["'']([^"'']+)["'']',
                '(?m)^\s*TF_VERSION_STRING\s*=\s*["'']([^"'']+)["'']'
            )
            foreach ($pattern in $patterns) {
                $match = [regex]::Match($text, $pattern)
                if ($match.Success) {
                    return [ordered]@{
                        package = $PackageName
                        version = $match.Groups[1].Value
                        source = $candidate
                        matched = $true
                        note = 'Version parsed statically; package was not imported.'
                    }
                }
            }

            return [ordered]@{
                package = $PackageName
                version = $null
                source = $candidate
                matched = $false
                note = 'Candidate version file exists but no supported assignment was parsed.'
            }
        }
        catch {
            return [ordered]@{
                package = $PackageName
                version = $null
                source = $candidate
                matched = $false
                note = $_.Exception.Message
            }
        }
    }

    return [ordered]@{
        package = $PackageName
        version = $null
        source = $null
        matched = $false
        note = 'No known static version file was found.'
    }
}

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\python-layout-diagnostics" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("legacy-python-layout-diagnostics-{0}.json" -f $fileTimestamp)
$batLinesPath = Join-Path $outputDirectory ("legacy-python-layout-bat-lines-{0}.txt" -f $fileTimestamp)

$pythonProbeCode = @'
import json, os, site, sys
payload = {
    "executable": sys.executable,
    "version": sys.version,
    "prefix": sys.prefix,
    "base_prefix": getattr(sys, "base_prefix", None),
    "path": list(sys.path),
    "site_packages": list(site.getsitepackages()) if hasattr(site, "getsitepackages") else [],
    "user_site": site.getusersitepackages() if hasattr(site, "getusersitepackages") else None,
    "enable_user_site": getattr(site, "ENABLE_USER_SITE", None),
    "pythonhome": os.environ.get("PYTHONHOME"),
    "pythonpath": os.environ.get("PYTHONPATH"),
}
print("__DFL_JSON_BEGIN__")
print(json.dumps(payload))
print("__DFL_JSON_END__")
'@

$pythonNoSiteCode = @'
import json, os, sys
payload = {
    "executable": sys.executable,
    "version": sys.version,
    "prefix": sys.prefix,
    "base_prefix": getattr(sys, "base_prefix", None),
    "path": list(sys.path),
    "pythonhome": os.environ.get("PYTHONHOME"),
    "pythonpath": os.environ.get("PYTHONPATH"),
}
print("__DFL_JSON_BEGIN__")
print(json.dumps(payload))
print("__DFL_JSON_END__")
'@

$normalProbe = Invoke-NativeCapture -Executable $pythonExe -Arguments @('-c', $pythonProbeCode)
$normalParsed = Parse-SentinelJson -Text $normalProbe.output
$noSiteProbe = Invoke-NativeCapture -Executable $pythonExe -Arguments @('-S', '-c', $pythonNoSiteCode)
$noSiteParsed = Parse-SentinelJson -Text $noSiteProbe.output

$pthFiles = @(Get-ChildItem -LiteralPath $pythonRoot -Filter '*._pth' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)
$pthRecords = @($pthFiles | ForEach-Object { Read-TextRecord -Path $_.FullName })
$sitePthFiles = @(Get-ChildItem -LiteralPath $sitePackages -Filter '*.pth' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)
$sitePthRecords = @($sitePthFiles | ForEach-Object { Read-TextRecord -Path $_.FullName })

$topLevelItems = @(Get-ChildItem -LiteralPath $sitePackages -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    [ordered]@{
        name = $_.Name
        full_path = $_.FullName
        is_directory = $_.PSIsContainer
        length = $(if ($_.PSIsContainer) { $null } else { [int64]$_.Length })
    }
})

$metadataDirectories = @(Get-ChildItem -LiteralPath $sitePackages -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)\.(dist-info|egg-info)$'
} | Sort-Object Name)

$metadataRecords = @($metadataDirectories | ForEach-Object {
    $metadataFile = @(
        (Join-Path $_.FullName 'METADATA'),
        (Join-Path $_.FullName 'PKG-INFO')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    $name = $null
    $version = $null
    $errorMessage = $null
    if ($metadataFile) {
        try {
            foreach ($line in @(Get-Content -LiteralPath $metadataFile -ErrorAction Stop)) {
                if ($null -eq $name -and $line -match '^Name:\s*(.+)$') { $name = $Matches[1].Trim() }
                if ($null -eq $version -and $line -match '^Version:\s*(.+)$') { $version = $Matches[1].Trim() }
                if ($name -and $version) { break }
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
        }
    }

    [ordered]@{
        directory = $_.FullName
        directory_name = $_.Name
        metadata_file = $metadataFile
        name = $name
        version = $version
        error = $errorMessage
    }
})

$selectedArtifacts = [ordered]@{}
$artifactPatterns = [ordered]@{
    tensorflow = @('tensorflow', 'tensorflow_core')
    numpy = @('numpy')
    scipy = @('scipy')
    h5py = @('h5py')
    opencv = @('cv2', 'cv2*.pyd')
    tf2onnx = @('tf2onnx')
    onnx = @('onnx')
    keras = @('keras')
    protobuf = @('google\protobuf')
}
foreach ($packageName in $artifactPatterns.Keys) {
    $matches = New-Object System.Collections.ArrayList
    foreach ($pattern in $artifactPatterns[$packageName]) {
        $literalCandidate = Join-Path $sitePackages $pattern
        if ($pattern -notmatch '[*?]') {
            if (Test-Path -LiteralPath $literalCandidate) {
                [void]$matches.Add($literalCandidate)
            }
        }
        else {
            foreach ($match in @(Get-ChildItem -LiteralPath $sitePackages -Filter $pattern -Force -ErrorAction SilentlyContinue)) {
                [void]$matches.Add($match.FullName)
            }
        }
    }
    $selectedArtifacts[$packageName] = @($matches | Select-Object -Unique)
}

$staticVersions = @(
    Find-StaticVersion -PackageName 'tensorflow' -CandidatePaths @(
        (Join-Path $sitePackages 'tensorflow\version.py'),
        (Join-Path $sitePackages 'tensorflow_core\version.py'),
        (Join-Path $sitePackages 'tensorflow\python\framework\versions.py'),
        (Join-Path $sitePackages 'tensorflow_core\python\framework\versions.py')
    ),
    Find-StaticVersion -PackageName 'numpy' -CandidatePaths @(
        (Join-Path $sitePackages 'numpy\version.py')
    ),
    Find-StaticVersion -PackageName 'scipy' -CandidatePaths @(
        (Join-Path $sitePackages 'scipy\version.py')
    ),
    Find-StaticVersion -PackageName 'h5py' -CandidatePaths @(
        (Join-Path $sitePackages 'h5py\version.py'),
        (Join-Path $sitePackages 'h5py\_version.py')
    ),
    Find-StaticVersion -PackageName 'tf2onnx' -CandidatePaths @(
        (Join-Path $sitePackages 'tf2onnx\version.py'),
        (Join-Path $sitePackages 'tf2onnx\__init__.py')
    ),
    Find-StaticVersion -PackageName 'onnx' -CandidatePaths @(
        (Join-Path $sitePackages 'onnx\version.py'),
        (Join-Path $sitePackages 'onnx\__init__.py')
    ),
    Find-StaticVersion -PackageName 'keras' -CandidatePaths @(
        (Join-Path $sitePackages 'keras\__init__.py')
    )
)

$topLevelBatFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Filter '*.bat' -File -Force -ErrorAction Stop | Sort-Object Name)
$batPattern = '(?i)^\s*(set|setx|call)\b|PYTHONHOME|PYTHONPATH|PATH=|CUDA|CUDNN|_internal|python-3\.6\.8|main\.py'
$batLines = New-Object System.Collections.ArrayList
foreach ($bat in $topLevelBatFiles) {
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $bat.FullName -ErrorAction Stop)) {
        $lineNumber++
        if ($line -match $batPattern) {
            [void]$batLines.Add([ordered]@{
                file = $bat.Name
                relative_path = Get-RelativePathText -FullPath $bat.FullName
                line = $lineNumber
                text = [string]$line
            })
        }
    }
}
@($batLines | ForEach-Object { "{0}:{1}: {2}" -f $_.relative_path, $_.line, $_.text }) |
    Set-Content -LiteralPath $batLinesPath -Encoding UTF8

$normalPath = @()
if ($normalParsed.value -and $normalParsed.value.path) { $normalPath = @($normalParsed.value.path) }
$noSitePath = @()
if ($noSiteParsed.value -and $noSiteParsed.value.path) { $noSitePath = @($noSiteParsed.value.path) }
$sitePackagesVisibleNormally = @($normalPath | Where-Object {
    [string]$_ -ieq $sitePackages
}).Count -gt 0
$sitePackagesVisibleWithoutSite = @($noSitePath | Where-Object {
    [string]$_ -ieq $sitePackages
}).Count -gt 0

$artifactPresenceCount = 0
foreach ($key in $selectedArtifacts.Keys) {
    if (@($selectedArtifacts[$key]).Count -gt 0) { $artifactPresenceCount++ }
}

$warnings = New-Object System.Collections.ArrayList
if ($metadataRecords.Count -le 1) {
    [void]$warnings.Add('The portable bundle exposes one or fewer dist-info/egg-info records. Package metadata inventory is not authoritative for this runtime.')
}
if (-not $sitePackagesVisibleNormally) {
    [void]$warnings.Add('The embedded site-packages directory is not present in the default sys.path probe.')
}
if ($artifactPresenceCount -eq 0) {
    [void]$warnings.Add('No selected runtime package directories or binaries were located under site-packages.')
}

$status = if (
    $normalProbe.exit_code -eq 0 -and
    $null -eq $normalParsed.error -and
    $noSiteProbe.exit_code -eq 0 -and
    $null -eq $noSiteParsed.error -and
    $topLevelBatFiles.Count -gt 0 -and
    $artifactPresenceCount -gt 0
) {
    'passed'
}
else {
    'blocked'
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'legacy_python_layout_diagnostics'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    runtime = [ordered]@{
        root = $runtimeRoot
        python_exe = $pythonExe
        python_root = $pythonRoot
        site_packages = $sitePackages
        deepfacelab_root = $deepFaceLabRoot
        main_py = $mainPy
        workspace = $workspacePath
    }
    python_path_probes = [ordered]@{
        normal = [ordered]@{
            exit_code = $normalProbe.exit_code
            parse_error = $normalParsed.error
            data = $normalParsed.value
            raw_output = $normalProbe.output
            site_packages_visible = $sitePackagesVisibleNormally
        }
        without_site = [ordered]@{
            exit_code = $noSiteProbe.exit_code
            parse_error = $noSiteParsed.error
            data = $noSiteParsed.value
            raw_output = $noSiteProbe.output
            site_packages_visible = $sitePackagesVisibleWithoutSite
        }
    }
    path_configuration = [ordered]@{
        python_dot_pth_files = @($pthRecords)
        site_pth_files = @($sitePthRecords)
    }
    filesystem_inventory = [ordered]@{
        site_packages_top_level_count = $topLevelItems.Count
        site_packages_top_level = @($topLevelItems)
        metadata_directory_count = $metadataRecords.Count
        metadata_records = @($metadataRecords)
        selected_artifacts = $selectedArtifacts
        selected_artifact_group_count = $artifactPresenceCount
        static_versions = @($staticVersions)
    }
    launcher_batch_files = [ordered]@{
        top_level_count = $topLevelBatFiles.Count
        top_level = @($topLevelBatFiles | ForEach-Object { $_.Name })
        relevant_line_count = @($batLines).Count
        relevant_lines_file = $batLinesPath
        relevant_lines_sample = @($batLines | Select-Object -First 160)
    }
    warnings = @($warnings | ForEach-Object { [string]$_ })
    safety = [ordered]@{
        tensorflow_imported = $false
        deepfacelab_main_executed = $false
        bat_files_executed = $false
        training_started = $false
        workspace_modified_intentionally = $false
        note = 'This diagnostic runs only Python sys.path/site probes and reads filesystem metadata and BAT text. It does not import TensorFlow or execute DeepFaceLab launchers.'
    }
    next_action = 'Use the discovered path configuration and package layout to build a separate controlled TensorFlow/CUDA/GPU import probe.'
}

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Legacy Python layout diagnostics completed.' -ForegroundColor Green
Write-Host ("Status: {0}" -f $status)
Write-Host ("Default sys.path includes site-packages: {0}" -f $sitePackagesVisibleNormally)
Write-Host ("Without-site sys.path includes site-packages: {0}" -f $sitePackagesVisibleWithoutSite)
Write-Host ("site-packages top-level items: {0}" -f $topLevelItems.Count)
Write-Host ("dist-info/egg-info records: {0}" -f $metadataRecords.Count)
Write-Host ("Selected artifact groups found: {0}" -f $artifactPresenceCount)
Write-Host ("Top-level BAT files read: {0}" -f $topLevelBatFiles.Count)
Write-Host ("Relevant launcher lines: {0}" -f @($batLines).Count)
Write-Host ("Warnings: {0}" -f @($warnings).Count)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ("BAT lines: {0}" -f $batLinesPath)
Write-Host ''
Write-Host 'TensorFlow, DeepFaceLab main.py, and bundled BAT files were not executed.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    site_packages_visible = $sitePackagesVisibleNormally
    metadata_count = $metadataRecords.Count
    selected_artifact_group_count = $artifactPresenceCount
    top_level_bat_count = $topLevelBatFiles.Count
    warning_count = @($warnings).Count
}

if ($status -ne 'passed') { exit 1 }
exit 0
