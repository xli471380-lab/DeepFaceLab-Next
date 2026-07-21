@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Inspect downloaded package

echo.
echo ============================================================
echo   DeepFaceLab-Next - Static package inspection
echo ============================================================
echo.
echo This tool will NOT run the downloaded EXE.
echo It will compute SHA256, inspect the signature, run Defender,
echo and use 7-Zip for archive listing and integrity testing if available.
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
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\inspect-runtime-package.ps1" -PackagePath "%PACKAGE%" -ProfilePath "%PROFILE%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\inspect-runtime-package.ps1" -PackagePath "%PACKAGE%"
)

if errorlevel 1 (
    echo.
    echo ERROR: Inspection did not complete.
    echo Copy the error shown above into the development chat.
    echo.
    pause
    exit /b 1
)

echo.
echo Inspection completed. Do not run the package yet.
echo Copy the generated JSON report into the development chat.
echo.
pause
exit /b 0
