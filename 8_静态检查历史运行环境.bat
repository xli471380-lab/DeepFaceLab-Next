@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Static legacy environment inspection

echo.
echo ============================================================
echo   DeepFaceLab-Next - Static legacy environment inspection
echo ============================================================
echo.
echo This tool reads installed package metadata and BAT file text.
echo It will NOT execute bundled BAT files, DeepFaceLab main.py,
echo TensorFlow imports, extraction, merge, or training commands.
echo.

set "PROFILE=config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1"
if not "%~1"=="" set "PROFILE=%~1"

if not exist "%PROFILE%" (
    echo ERROR: Local legacy runtime profile was not found:
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
set /p "CONFIRM=Type INSPECT to continue: "
if /i not "%CONFIRM%"=="INSPECT" (
    echo.
    echo Cancelled.
    echo.
    pause
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\inspect-legacy-runtime-environment.ps1" -ProfilePath "%PROFILE%"

if errorlevel 1 (
    echo.
    echo ERROR: Static environment inspection did not pass.
    echo Copy the error shown above into the development chat.
    echo.
    pause
    exit /b 1
)

echo.
echo Static inspection completed. No bundled BAT or main.py was run.
echo Copy the generated JSON report into the development chat.
echo.
pause
exit /b 0
