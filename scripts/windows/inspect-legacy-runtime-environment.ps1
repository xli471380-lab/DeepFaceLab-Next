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
$ffmpegExe = Read-ProfileValue -Name 'FFmpegExe'
$deepFaceLabRoot = Read-ProfileValue -Name 'DeepFaceLabRoot'
$mainPy = Read-ProfileValue -Name 'MainPy'
$workspacePath = Read-ProfileValue -Name 'WorkspacePath'

$requiredPaths = [ordered]@{
    runtime_root = $runtimeRoot
    python_exe = $pythonExe
    ffmpeg_exe = $ffmpegExe
    deepfacelab_root = $deepFaceLabRoot
    main_py = $mainPy
    workspace = $workspacePath
}
foreach ($entry in $requiredPaths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        throw ("Required profile path does not exist: {0} = {1}" -f $entry.Key, $entry.Value)
    }
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

function Normalize-PackageName {
    param([Parameter(Mandatory = $true)][string]$Name)
    return (($Name.ToLowerInvariant()) -replace '[-_.]+', '-')
}

$timestamp = (Get-Date).ToUniversalTime()
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\runtime-environment-inspection" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$reportPath = Join-Path $outputDirectory ("legacy-runtime-environment-inspection-{0}.json" -f $fileTimestamp)
$packageInventoryPath = Join-Path $outputDirectory ("legacy-runtime-package-inventory-{0}.json" -f $fileTimestamp)
$batLinesPath = Join-Path $outputDirectory ("legacy-runtime-bat-environment-lines-{0}.txt" -f $fileTimestamp)

# Use package metadata directly instead of pip's console formatter. Old pip builds
# can emit warnings beside JSON, which makes a valid package list look empty.
$packageCode = 'import json,pkg_resources;print(json.dumps([dict(name=d.project_name,version=d.version,location=d.location) for d in pkg_resources.working_set]))'
$packageProbe = Invoke-NativeCapture -Executable $pythonExe -Arguments @('-c', $packageCode)
$packageParseError = $null
$allPackages = @()
if ($packageProbe.exit_code -eq 0 -and -not [string]::IsNullOrWhiteSpace($packageProbe.output)) {
    try {
        $allPackages = @($packageProbe.output | ConvertFrom-Json)
    }
    catch {
        $packageParseError = $_.Exception.Message
    }
}
else {
    $packageParseError = $packageProbe.output
}

if ($allPackages.Count -gt 0) {
    @($allPackages | Sort-Object name) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $packageInventoryPath -Encoding UTF8
}

$wanted = @(
    'numpy',
    'h5py',
    'opencv-python',
    'scipy',
    'tensorflow',
    'tensorflow-gpu',
    'tf2onnx',
    'onnx',
    'keras',
    'protobuf'
)
$wantedNormalized = @($wanted | ForEach-Object { Normalize-PackageName -Name $_ })
$selectedPackages = @($allPackages | Where-Object {
    $name = Normalize-PackageName -Name ([string]$_.name)
    $wantedNormalized -contains $name
} | Sort-Object name)

$batFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Filter '*.bat' -File -Recurse -Force -ErrorAction Stop | Sort-Object FullName)
$topLevelBatFiles = @($batFiles | Where-Object { $_.DirectoryName.TrimEnd('\') -ieq $runtimeRoot.TrimEnd('\') })

$batInventory = @($batFiles | ForEach-Object {
    [ordered]@{
        relative_path = $_.FullName.Substring($runtimeRoot.TrimEnd('\').Length).TrimStart('\')
        full_path = $_.FullName
        size_bytes = [int64]$_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
})

$environmentLinePattern = '(?i)(^|\s)(set|setx)\s+[^=]*(PATH|PYTHONHOME|PYTHONPATH|CUDA|CUDNN|DFL|WORKSPACE)|_internal|python-3\.6\.8|ffmpeg\.exe|main\.py|CUDA\\|CUDNN\\'
$environmentLines = New-Object System.Collections.ArrayList
foreach ($bat in $batFiles) {
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $bat.FullName -ErrorAction Stop)) {
        $lineNumber++
        if ($line -match $environmentLinePattern) {
            [void]$environmentLines.Add([ordered]@{
                relative_path = $bat.FullName.Substring($runtimeRoot.TrimEnd('\').Length).TrimStart('\')
                line = $lineNumber
                text = [string]$line
            })
        }
    }
}

@($environmentLines | ForEach-Object {
    "{0}:{1}: {2}" -f $_.relative_path, $_.line, $_.text
}) | Set-Content -LiteralPath $batLinesPath -Encoding UTF8

$status = if ($packageProbe.exit_code -eq 0 -and $null -eq $packageParseError -and $allPackages.Count -gt 0 -and $batFiles.Count -gt 0) {
    'passed'
}
else {
    'blocked'
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    phase = 'legacy_runtime_static_environment_inspection'
    status = $status
    machine_id = $machineId
    environment_id = $environmentId
    profile_path = $profileResolved
    runtime = [ordered]@{
        root = $runtimeRoot
        python_exe = $pythonExe
        ffmpeg_exe = $ffmpegExe
        deepfacelab_root = $deepFaceLabRoot
        main_py = $mainPy
        workspace = $workspacePath
    }
    package_inventory = [ordered]@{
        method = 'python_pkg_resources_working_set'
        exit_code = $packageProbe.exit_code
        parse_error = $packageParseError
        total_count = $allPackages.Count
        output_file = $(if (Test-Path -LiteralPath $packageInventoryPath) { $packageInventoryPath } else { $null })
        selected_packages = @($selectedPackages)
    }
    batch_files = [ordered]@{
        total_count = $batFiles.Count
        top_level_count = $topLevelBatFiles.Count
        top_level = @($topLevelBatFiles | ForEach-Object { $_.Name })
        inventory = @($batInventory)
        environment_line_count = @($environmentLines).Count
        environment_lines_file = $batLinesPath
        environment_lines_sample = @($environmentLines | Select-Object -First 120)
    }
    safety = [ordered]@{
        bat_files_executed = $false
        main_py_executed = $false
        tensorflow_imported = $false
        training_started = $false
        note = 'This inspection reads package metadata and BAT text only. It does not execute any bundled BAT file, DeepFaceLab main.py, TensorFlow import, extraction, merge, or training command.'
    }
    next_action = 'Review package versions and static BAT environment setup before a separate controlled TensorFlow/CUDA/GPU import probe.'
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'Legacy runtime static environment inspection completed.' -ForegroundColor Green
Write-Host ("Status: {0}" -f $status)
Write-Host ("Installed package records: {0}" -f $allPackages.Count)
Write-Host ("Selected package records: {0}" -f $selectedPackages.Count)
Write-Host ("BAT files read: {0}" -f $batFiles.Count)
Write-Host ("Relevant BAT environment lines: {0}" -f @($environmentLines).Count)
Write-Host ("Report: {0}" -f $reportPath)
Write-Host ("BAT lines: {0}" -f $batLinesPath)
Write-Host ''
Write-Host 'No bundled BAT file or DeepFaceLab main.py was executed.' -ForegroundColor Yellow

[PSCustomObject]@{
    report_path = $reportPath
    status = $status
    package_count = $allPackages.Count
    selected_package_count = $selectedPackages.Count
    bat_count = $batFiles.Count
    environment_line_count = @($environmentLines).Count
}

if ($status -ne 'passed') { exit 1 }
exit 0
