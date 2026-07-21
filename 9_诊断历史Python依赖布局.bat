@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Legacy Python layout diagnostics

echo.
echo ============================================================
echo   DeepFaceLab-Next - Legacy Python layout diagnostics
echo ============================================================
echo.
echo This tool inspects Python path files, sys.path, site-packages,
echo package folders, static version files, and launcher BAT text.
echo.
echo It will NOT import TensorFlow or execute DeepFaceLab main.py,
echo bundled BAT files, extraction, merge, or training commands.
echo.
echo The staged wrapper reports the exact active stage. Each embedded
echo Python probe is limited to 45 seconds, and the overall read-only
echo process is limited to 3 minutes.
echo.

set "PROFILE=config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1"
if not "%~1"=="" set "PROFILE=%~1"

if not exist "%PROFILE%" (
    echo ERROR: Local historical runtime profile was not found:
    echo %PROFILE%
    echo.
    echo Run step 7 first.
    echo.
    pause
    exit /b 1
)

echo Local profile:
echo %PROFILE%
echo.
set /p "CONFIRM=Type DIAGNOSE to continue: "
if /i not "%CONFIRM%"=="DIAGNOSE" (
    echo.
    echo Cancelled.
    echo.
    pause
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\run-legacy-python-layout-diagnostics.ps1" -ProfilePath "%PROFILE%" -TimeoutSeconds 180 -PythonProbeTimeoutSeconds 45

if errorlevel 1 (
    echo.
    echo ERROR: Legacy Python layout diagnostics did not pass.
    echo Copy the stage and report output shown above into the development chat.
    echo.
    pause
    exit /b 1
)

echo.
echo Python layout diagnostics completed.
echo TensorFlow and DeepFaceLab main.py were not executed.
echo Copy the generated JSON report into the development chat.
echo.
pause
exit /b 0
