[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath
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

$machineId = Get-ProfileValue 'MachineId'
$environmentId = Get-ProfileValue 'EnvironmentId'
$runtimeRoot = Get-ProfileValue 'RuntimeRoot'
$pythonExe = Get-ProfileValue 'PythonExe'
$deepFaceLabRoot = Get-ProfileValue 'DeepFaceLabRoot'
$mainPy = Get-ProfileValue 'MainPy'
$workspacePath = Get-ProfileValue 'WorkspacePath'

foreach ($path in @($runtimeRoot, $pythonExe, $deepFaceLabRoot, $mainPy, $workspacePath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required path does not exist: $path" }
}

$pythonRoot = Split-Path -Parent $pythonExe
$sitePackages = Join-Path $pythonRoot 'Lib\site-packages'
if (-not (Test-Path -LiteralPath $sitePackages -PathType Container)) {
    throw "site-packages does not exist: $sitePackages"
}

function Invoke-NativeText {
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
        return [ordered]@{ exit_code = -1; output = $_.Exception.ToString() }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Convert-SentinelJson {
    param([AllowEmptyString()][string]$Text)
    $match = [regex]::Match($Text, '(?s)__DFL_JSON_BEGIN__\s*(.*?)\s*__DFL_JSON_END__')
    if (-not $match.Success) {
        return [ordered]@{ value = $null; error = 'Sentinel JSON markers were not found.' }
    }
    try {
        return [ordered]@{ value = ($match.Groups[1].Value | ConvertFrom-Json); error = $null }
    }
    catch {
        return [ordered]@{ value = $null; error = $_.Exception.Message }
    }
}

function Read-TextFileRecord {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        return [ordered]@{
            path = $Path
            content = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
            error = $null
        }
    }
    catch {
        return [ordered]@{ path = $Path; content = $null; error = $_.Exception.Message }
    }
}

function Get-StaticVersionRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Package,
        [Parameter(Mandatory = $true)][string[]]$Candidates
    )
    foreach ($candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
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
                        package = $Package
                        version = $match.Groups[1].Value
                        source = $candidate
                        matched = $true
                    }
                }
            }
            return [ordered]@{
                package = $Package
                version = $null
                source = $candidate
                matched = $false
            }
        }
        catch {
            return [ordered]@{
                package = $Package
                version = $null
                source = $candidate
                matched = $false
                error = $_.Exception.Message
            }
        }
    }
    return [ordered]@{
        package = $Package
        version = $null
        source = $null
        matched = $false
    }
}

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\python-layout-inspection" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("legacy-python-layout-inspection-{0}.json" -f $fileTimestamp)
$batLinesPath = Join-Path $outputDirectory ("legacy-python-launcher-lines-{0}.txt" -f $fileTimestamp)

$normalCode = 'import json,os,site,sys;d=dict(executable=sys.executable,version=sys.version,prefix=sys.prefix,path=list(sys.path),site_packages=list(site.getsitepackages()) if hasattr(site,"getsitepackages") else [],pythonhome=os.environ.get("PYTHONHOME"),pythonpath=os.environ.get("PYTHONPATH"));print("__DFL_JSON_BEGIN__");print(json.dumps(d));print("__DFL_JSON_END__")'
$noSiteCode = 'import json,os,sys;d=dict(executable=sys.executable,version=sys.version,prefix=sys.prefix,path=list(sys.path),pythonhome=os.environ.get("PYTHONHOME"),pythonpath=os.environ.get("PYTHONPATH"));print("__DFL_JSON_BEGIN__");print(json.dumps(d));print("__DFL_JSON_END__")'

$normalProbe = Invoke-NativeText -Executable $pythonExe -Arguments @('-c', $normalCode)
$normalJson = Convert-SentinelJson -Text $normalProbe.output
$noSiteProbe = Invoke-NativeText -Executable $pythonExe -Arguments @('-S', '-c', $noSiteCode)
$noSiteJson = Convert-SentinelJson -Text $noSiteProbe.output

$normalPath = @()
if ($normalJson.value -and $normalJson.value.path) { $normalPath = @($normalJson.value.path) }
$noSitePath = @()
if ($noSiteJson.value -and $noSiteJson.value.path) { $noSitePath = @($noSiteJson.value.path) }
$siteVisibleNormal = @($normalPath | Where-Object { [string]$_ -ieq $sitePackages }).Count -gt 0
$siteVisibleNoSite = @($noSitePath | Where-Object { [string]$_ -ieq $sitePackages }).Count -gt 0

$pythonDotPthFiles = @(Get-ChildItem -LiteralPath $pythonRoot -Filter '*._pth' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)
$pythonDotPthRecords = @($pythonDotPthFiles | ForEach-Object { Read-TextFileRecord -Path $_.FullName })
$sitePthFiles = @(Get-ChildItem -LiteralPath $sitePackages -Filter '*.pth' -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)
$sitePthRecords = @($sitePthFiles | ForEach-Object { Read-TextFileRecord -Path $_.FullName })

$siteTopLevel = @(Get-ChildItem -LiteralPath $sitePackages -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    [ordered]@{
        name = $_.Name
        full_path = $_.FullName
        is_directory = $_.PSIsContainer
        size_bytes = $(if ($_.PSIsContainer) { $null } else { [int64]$_.Length })
    }
})

$metadataDirs = @(Get-ChildItem -LiteralPath $sitePackages -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)\.(dist-info|egg-info)$'
} | Sort-Object Name)
$metadataRecords = @($metadataDirs | ForEach-Object {
    [ordered]@{ name = $_.Name; full_path = $_.FullName }
})

$artifactMap = [ordered]@{}
$artifactCandidates = [ordered]@{
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
foreach ($package in $artifactCandidates.Keys) {
    $found = New-Object System.Collections.ArrayList
    foreach ($relative in $artifactCandidates[$package]) {
        if ($relative -match '[*?]') {
            foreach ($item in @(Get-ChildItem -LiteralPath $sitePackages -Filter $relative -Force -ErrorAction SilentlyContinue)) {
                [void]$found.Add($item.FullName)
            }
        }
        else {
            $candidate = Join-Path $sitePackages $relative
            if (Test-Path -LiteralPath $candidate) { [void]$found.Add($candidate) }
        }
    }
    $artifactMap[$package] = @($found | Select-Object -Unique)
}

$versionRecords = New-Object System.Collections.ArrayList
[void]$versionRecords.Add((Get-StaticVersionRecord -Package 'tensorflow' -Candidates @(
    (Join-Path $sitePackages 'tensorflow\version.py'),
    (Join-Path $sitePackages 'tensorflow_core\version.py'),
    (Join-Path $sitePackages 'tensorflow\python\framework\versions.py'),
    (Join-Path $sitePackages 'tensorflow_core\python\framework\versions.py')
)))
[void]$versionRecords.Add((Get-StaticVersionRecord -Package 'numpy' -Candidates @(
    (Join-Path $sitePackages 'numpy\version.py')
)))
[void]$versionRecords.Add((Get-StaticVersionRecord -Package 'scipy' -Candidates @(
    (Join-Path $sitePackages 'scipy\version.py')
)))
[void]$versionRecords.Add((Get-StaticVersionRecord -Package 'h5py' -Candidates @(
    (Join-Path $sitePackages 'h5py\version.py'),
    (Join-Path $sitePackages 'h5py\_version.py')
)))
[void]$versionRecords.Add((Get-StaticVersionRecord -Package 'tf2onnx' -Candidates @(
    (Join-Path $sitePackages 'tf2onnx\version.py'),
    (Join-Path $sitePackages 'tf2onnx\__init__.py')
)))
[void]$versionRecords.Add((Get-StaticVersionRecord -Package 'onnx' -Candidates @(
    (Join-Path $sitePackages 'onnx\version.py'),
    (Join-Path $sitePackages 'onnx\__init__.py')
)))
[void]$versionRecords.Add((Get-StaticVersionRecord -Package 'keras' -Candidates @(
    (Join-Path $sitePackages 'keras\__init__.py')
)))

$topLevelBatFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Filter '*.bat' -File -Force -ErrorAction Stop | Sort-Object Name)
$launcherLines = New-Object System.Collections.ArrayList
$launcherPattern = '(?i)^\s*(set|setx|call)\b|PYTHONHOME|PYTHONPATH|PATH=|CUDA|CUDNN|_internal|python-3\.6\.8|main\.py'
foreach ($bat in $topLevelBatFiles) {
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $bat.FullName -ErrorAction Stop)) {
        $lineNumber++
        if ($line -match $launcherPattern) {
            [void]$launcherLines.Add([ordered]@{
                file = $bat.Name
                line = $lineNumber
                text = [string]$line
            })
        }
    }
}
@($launcherLines | ForEach-Object { "{0}:{1}: {2}" -f $_.file, $_.line, $_.text }) |
    Set-Content -LiteralPath $batLinesPath -Encoding UTF8

$artifactGroupCount = 0
foreach ($package in $artifactMap.Keys) {
    if (@($artifactMap[$package]).Count -gt 0) { $artifactGroupCount++ }
}

$warnings = New-Object System.Collections.ArrayList
if ($metadataRecords.Count -le 1) {
    [void]$warnings.Add('Only one or fewer dist-info/egg-info directories are present; pip/pkg_resources inventory is not authoritative for this portable bundle.')
}
if (-not $siteVisibleNormal) {
    [void]$warnings.Add('The default embedded Python sys.path does not contain Lib\site-packages.')
}
if ($artifactGroupCount -eq 0) {
    [void]$warnings.Add('No selected package artifacts were found under Lib\site-packages.')
}

$status = if (
    $normalProbe.exit_code -eq 0 -and
    $null -eq $normalJson.error -and
    $noSiteProbe.exit_code -eq 0 -and
    $null -eq $noSiteJson.error -and
    $topLevelBatFiles.Count -gt 0 -and
    $artifactGroupCount -gt 0
) { 'passed' } else { 'blocked' }

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'legacy_python_layout_inspection'
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
    python_path = [ordered]@{
        normal = [ordered]@{
            exit_code = $normalProbe.exit_code
            parse_error = $normalJson.error
            data = $normalJson.value
            site_packages_visible = $siteVisibleNormal
            raw_output = $normalProbe.output
        }
        without_site = [ordered]@{
            exit_code = $noSiteProbe.exit_code
            parse_error = $noSiteJson.error
            data = $noSiteJson.value
            site_packages_visible = $siteVisibleNoSite
            raw_output = $noSiteProbe.output
        }
    }
    path_files = [ordered]@{
        python_dot_pth = @($pythonDotPthRecords)
        site_pth = @($sitePthRecords)
    }
    filesystem = [ordered]@{
        site_packages_top_level_count = $siteTopLevel.Count
        site_packages_top_level = @($siteTopLevel)
        metadata_directory_count = $metadataRecords.Count
        metadata_directories = @($metadataRecords)
        selected_artifacts = $artifactMap
        selected_artifact_group_count = $artifactGroupCount
        static_versions = @($versionRecords | ForEach-Object { $_ })
    }
    launchers = [ordered]@{
        top_level_bat_count = $topLevelBatFiles.Count
        top_level_bat_names = @($topLevelBatFiles | ForEach-Object { $_.Name })
        relevant_line_count = @($launcherLines).Count
        relevant_lines_file = $batLinesPath
        relevant_lines_sample = @($launcherLines | Select-Object -First 160)
    }
    warnings = @($warnings | ForEach-Object { [string]$_ })
    safety = [ordered]@{
        tensorflow_imported = $false
        bat_files_executed = $false
        main_py_executed = $false
        training_started = $false
        workspace_modified_intentionally = $false
        note = 'This inspection runs Python sys.path/site probes and reads filesystem metadata and BAT text only.'
    }
    next_action = 'Use the discovered path layout to create a separate controlled TensorFlow, CUDA DLL, and GPU visibility probe.'
}

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Legacy Python layout inspection completed.' -ForegroundColor Green
Write-Host ("Status: {0}" -f $status)
Write-Host ("Default sys.path includes site-packages: {0}" -f $siteVisibleNormal)
Write-Host ("Without-site sys.path includes site-packages: {0}" -f $siteVisibleNoSite)
Write-Host ("site-packages top-level items: {0}" -f $siteTopLevel.Count)
Write-Host ("dist-info/egg-info directories: {0}" -f $metadataRecords.Count)
Write-Host ("Selected artifact groups found: {0}" -f $artifactGroupCount)
Write-Host ("Top-level BAT files read: {0}" -f $topLevelBatFiles.Count)
Write-Host ("Relevant launcher lines: {0}" -f @($launcherLines).Count)
Write-Host ("Warnings: {0}" -f @($warnings).Count)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ("Launcher lines: {0}" -f $batLinesPath)
Write-Host ''
Write-Host 'TensorFlow, DeepFaceLab main.py, and bundled BAT files were not executed.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    site_packages_visible = $siteVisibleNormal
    metadata_count = $metadataRecords.Count
    selected_artifact_group_count = $artifactGroupCount
    top_level_bat_count = $topLevelBatFiles.Count
    warning_count = @($warnings).Count
}

if ($status -ne 'passed') { exit 1 }
exit 0
