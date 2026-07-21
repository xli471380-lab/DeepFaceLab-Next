@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Defender scan diagnostics

echo.
echo ============================================================
echo   DeepFaceLab-Next - Defender scan diagnostics
echo ============================================================
echo.
echo This tool does not change Defender settings or exclusions.
echo It only reads antivirus status and requests a custom scan.
echo.

set "PACKAGE=F:\FDeepFaceLab-Historical-Downloads\DeepFaceLab\DeepFaceLab_NVIDIA_RTX3000_series_build_11_20_2021.exe"
set "PROFILE="
for /f "delims=" %%P in ('dir /b /a-d "config\local\*.psd1" 2^>nul') do if not defined PROFILE set "PROFILE=config\local\%%P"

if not exist "%PACKAGE%" (
    echo Default package path was not found:
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

if defined PROFILE (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\diagnose-defender-scan.ps1" -PackagePath "%PACKAGE%" -ProfilePath "%PROFILE%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\diagnose-defender-scan.ps1" -PackagePath "%PACKAGE%"
)

if errorlevel 1 (
    echo.
    echo ERROR: Defender diagnostics did not complete.
    echo Copy the error shown above into the development chat.
    echo.
    pause
    exit /b 1
)

echo.
echo Defender diagnostics completed.
echo Copy the generated JSON report into the development chat.
echo.
pause
exit /b 0
