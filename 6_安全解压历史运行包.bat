@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Safe legacy runtime extraction

echo.
echo ============================================================
echo   DeepFaceLab-Next - Safe legacy runtime extraction
echo ============================================================
echo.
echo This tool will NOT execute the downloaded SFX.
echo It verifies SHA256, rejects unsafe archive paths, tests the
echo archive, extracts with 7-Zip, and creates an inventory report.
echo.

set "PACKAGE=F:\FDeepFaceLab-Historical-Downloads\DeepFaceLab\DeepFaceLab_NVIDIA_RTX3000_series_build_11_20_2021.exe"
set "DESTINATION=F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120"
set "EXPECTED_SHA256=4CA31C30CA8F683A825A643E7090811D750C1250775537DCDB5C80D5F3B7F722"
set "PROFILE="

if not "%~1"=="" set "PACKAGE=%~1"
if not "%~2"=="" set "DESTINATION=%~2"
if not "%~3"=="" set "PROFILE=%~3"

if not defined PROFILE (
    for /f "delims=" %%P in ('dir /b /a-d "config\local\*.psd1" 2^>nul') do if not defined PROFILE set "PROFILE=config\local\%%P"
)

if not exist "%PACKAGE%" (
    echo Package path was not found:
    echo %PACKAGE%
    echo.
    set /p "PACKAGE=Enter the full package path: "
)

if not exist "%PACKAGE%" (
    echo.
    echo ERROR: Package file was not found.
    echo.
    pause
    exit /b 1
)

echo Package:
echo %PACKAGE%
echo.
echo Destination:
echo %DESTINATION%
echo.
if defined PROFILE (
    echo Report profile:
    echo %PROFILE%
    echo.
)
echo The destination must be empty. Existing files will not be overwritten.
echo.
set /p "CONFIRM=Type EXTRACT to continue: "
if /i not "%CONFIRM%"=="EXTRACT" (
    echo.
    echo Cancelled.
    echo.
    pause
    exit /b 2
)

if defined PROFILE (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\extract-and-inspect-legacy-runtime.ps1" -PackagePath "%PACKAGE%" -DestinationPath "%DESTINATION%" -ExpectedSha256 "%EXPECTED_SHA256%" -ProfilePath "%PROFILE%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\extract-and-inspect-legacy-runtime.ps1" -PackagePath "%PACKAGE%" -DestinationPath "%DESTINATION%" -ExpectedSha256 "%EXPECTED_SHA256%"
)

if errorlevel 1 (
    echo.
    echo ERROR: Extraction did not complete.
    echo Copy the error shown above into the development chat.
    echo.
    pause
    exit /b 1
)

echo.
echo Extraction completed. Do NOT run any extracted file yet.
echo Scan the destination folder with the active antivirus, then copy
echo the JSON report into the development chat.
echo.
pause
exit /b 0
