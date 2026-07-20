[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$ProfilePath,
    [switch]$SkipDefender
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$file = Get-Item -LiteralPath $resolvedPackage -Force

if (-not $file.PSIsContainer -and $file.Extension -ieq '.exe') {
    # Expected package type.
}
else {
    throw 'PackagePath must point to the downloaded DeepFaceLab EXE file.'
}

$machineId = $env:COMPUTERNAME.ToLowerInvariant()
$environmentId = 'package-inspection'
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

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
        return [ordered]@{
            executable = $Executable
            arguments = @($Arguments)
            exit_code = $exitCode
            output = ($lines -join [Environment]::NewLine).Trim()
        }
    }
    catch {
        return [ordered]@{
            executable = $Executable
            arguments = @($Arguments)
            exit_code = -1
            output = $_.Exception.Message
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Find-SevenZip {
    $command = Get-Command '7z.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe' } else { $null })
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Find-DefenderCli {
    $platformRoot = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
    if (Test-Path -LiteralPath $platformRoot -PathType Container) {
        $latest = Get-ChildItem -LiteralPath $platformRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'MpCmdRun.exe' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($latest) { return $latest }
    }

    $legacy = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (Test-Path -LiteralPath $legacy -PathType Leaf) {
        return (Resolve-Path -LiteralPath $legacy).Path
    }
    return $null
}

$timestamp = (Get-Date).ToUniversalTime()
$outputDirectory = Join-Path $repoRoot ("artifacts\p0\{0}\{1}\package-inspection" -f $machineId, $environmentId)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$fileTimestamp = $timestamp.ToString('yyyyMMddTHHmmssZ')
$reportPath = Join-Path $outputDirectory ("runtime-package-inspection-{0}.json" -f $fileTimestamp)
$sevenZipListPath = Join-Path $outputDirectory ("runtime-package-7zip-list-{0}.txt" -f $fileTimestamp)
$sevenZipTestPath = Join-Path $outputDirectory ("runtime-package-7zip-test-{0}.txt" -f $fileTimestamp)
$defenderLogPath = Join-Path $outputDirectory ("runtime-package-defender-{0}.txt" -f $fileTimestamp)

$hash = Get-FileHash -LiteralPath $resolvedPackage -Algorithm SHA256
$signature = Get-AuthenticodeSignature -LiteralPath $resolvedPackage
$versionInfo = $file.VersionInfo

$headerBytes = New-Object byte[] 2
$stream = [System.IO.File]::Open($resolvedPackage, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
try {
    [void]$stream.Read($headerBytes, 0, 2)
}
finally {
    $stream.Dispose()
}
$hasMzHeader = ($headerBytes[0] -eq 0x4D -and $headerBytes[1] -eq 0x5A)

$sevenZipPath = Find-SevenZip
$sevenZip = [ordered]@{
    available = (-not [string]::IsNullOrWhiteSpace($sevenZipPath))
    path = $sevenZipPath
    list_exit_code = $null
    list_output_file = $null
    test_exit_code = $null
    test_output_file = $null
    archive_type = $null
    entry_count = $null
    bat_count = $null
    exe_count = $null
    dll_count = $null
    contains_internal = $false
    contains_workspace = $false
}

if ($sevenZip.available) {
    $listResult = Invoke-NativeCapture -Executable $sevenZipPath -Arguments @('l', '-slt', $resolvedPackage)
    $listResult.output | Set-Content -LiteralPath $sevenZipListPath -Encoding UTF8
    $sevenZip.list_exit_code = $listResult.exit_code
    $sevenZip.list_output_file = $sevenZipListPath

    $testResult = Invoke-NativeCapture -Executable $sevenZipPath -Arguments @('t', $resolvedPackage)
    $testResult.output | Set-Content -LiteralPath $sevenZipTestPath -Encoding UTF8
    $sevenZip.test_exit_code = $testResult.exit_code
    $sevenZip.test_output_file = $sevenZipTestPath

    $pathLines = @($listResult.output -split "`r?`n" | Where-Object { $_ -like 'Path = *' })
    $entryPaths = @($pathLines | ForEach-Object { $_.Substring(7) })
    $archiveTypeLine = @($listResult.output -split "`r?`n" | Where-Object { $_ -like 'Type = *' } | Select-Object -First 1)
    if (@($archiveTypeLine).Count -gt 0) {
        $sevenZip.archive_type = ([string]$archiveTypeLine[0]).Substring(7)
    }
    $sevenZip.entry_count = @($entryPaths).Count
    $sevenZip.bat_count = @($entryPaths | Where-Object { $_ -match '(?i)\.bat$' }).Count
    $sevenZip.exe_count = @($entryPaths | Where-Object { $_ -match '(?i)\.exe$' }).Count
    $sevenZip.dll_count = @($entryPaths | Where-Object { $_ -match '(?i)\.dll$' }).Count
    $sevenZip.contains_internal = (@($entryPaths | Where-Object { $_ -match '(?i)(^|[\\/])_internal([\\/]|$)' }).Count -gt 0)
    $sevenZip.contains_workspace = (@($entryPaths | Where-Object { $_ -match '(?i)(^|[\\/])workspace([\\/]|$)' }).Count -gt 0)
}

$defender = [ordered]@{
    requested = (-not $SkipDefender.IsPresent)
    available = $false
    path = $null
    exit_code = $null
    output_file = $null
}

if (-not $SkipDefender.IsPresent) {
    $defenderPath = Find-DefenderCli
    if ($defenderPath) {
        $defender.available = $true
        $defender.path = $defenderPath
        $defenderResult = Invoke-NativeCapture -Executable $defenderPath -Arguments @('-Scan', '-ScanType', '3', '-File', $resolvedPackage)
        $defenderResult.output | Set-Content -LiteralPath $defenderLogPath -Encoding UTF8
        $defender.exit_code = $defenderResult.exit_code
        $defender.output_file = $defenderLogPath
    }
}

$warnings = @()
if ($signature.Status -ne 'Valid') {
    $warnings += ("Authenticode status is {0}; this package has no verified publisher signature." -f $signature.Status)
}
if (-not $sevenZip.available) {
    $warnings += '7-Zip was not found, so archive listing and integrity testing were not performed.'
}
elseif ($sevenZip.test_exit_code -ne 0) {
    $warnings += ("7-Zip archive test returned exit code {0}." -f $sevenZip.test_exit_code)
}
if ($defender.requested -and -not $defender.available) {
    $warnings += 'Microsoft Defender command-line scanner was not found.'
}
elseif ($defender.available -and $defender.exit_code -ne 0) {
    $warnings += ("Microsoft Defender scan returned exit code {0}; inspect its log before proceeding." -f $defender.exit_code)
}

$report = [ordered]@{
    schema_version = 1
    generated_at_utc = $timestamp.ToString('o')
    repository_commit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    machine_id = $machineId
    environment_id = $environmentId
    package = [ordered]@{
        name = $file.Name
        full_path = $file.FullName
        size_bytes = [int64]$file.Length
        last_write_time = $file.LastWriteTime.ToString('o')
        sha256 = $hash.Hash
        mz_header = $hasMzHeader
        version_info = [ordered]@{
            file_description = $versionInfo.FileDescription
            file_version = $versionInfo.FileVersion
            product_name = $versionInfo.ProductName
            product_version = $versionInfo.ProductVersion
            company_name = $versionInfo.CompanyName
            original_filename = $versionInfo.OriginalFilename
        }
        authenticode = [ordered]@{
            status = $signature.Status.ToString()
            status_message = $signature.StatusMessage
            signer_subject = $(if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null })
            signer_thumbprint = $(if ($signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { $null })
        }
    }
    seven_zip = $sevenZip
    microsoft_defender = $defender
    warnings = @($warnings)
    safety_note = 'This inspection does not execute the downloaded package. A clean local scan and valid archive structure reduce risk but do not prove authorship or complete safety.'
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'DeepFaceLab runtime package static inspection completed.' -ForegroundColor Green
Write-Host ("Package: {0}" -f $file.FullName)
Write-Host ("Size: {0} bytes" -f $file.Length)
Write-Host ("SHA256: {0}" -f $hash.Hash)
Write-Host ("Authenticode: {0}" -f $signature.Status)
Write-Host ("MZ executable header: {0}" -f $hasMzHeader)
if ($sevenZip.available) {
    Write-Host ("7-Zip archive test exit code: {0}" -f $sevenZip.test_exit_code)
    Write-Host ("7-Zip entries: {0}" -f $sevenZip.entry_count)
} else {
    Write-Host '7-Zip: not found' -ForegroundColor Yellow
}
if ($defender.available) {
    Write-Host ("Microsoft Defender exit code: {0}" -f $defender.exit_code)
} elseif ($defender.requested) {
    Write-Host 'Microsoft Defender CLI: not found' -ForegroundColor Yellow
}
Write-Host ("Report: {0}" -f $reportPath)

if (@($warnings).Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host ("- {0}" -f $warning) -ForegroundColor Yellow
    }
}

[PSCustomObject]@{
    report_path = $reportPath
    sha256 = $hash.Hash
    signature_status = $signature.Status.ToString()
    seven_zip_test_exit_code = $sevenZip.test_exit_code
    defender_exit_code = $defender.exit_code
    warning_count = @($warnings).Count
}
