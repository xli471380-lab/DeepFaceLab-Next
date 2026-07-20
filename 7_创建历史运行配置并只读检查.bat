@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Legacy runtime read-only probe

echo.
echo ============================================================
echo   DeepFaceLab-Next - Legacy runtime read-only probe
echo ============================================================
echo.
echo This tool creates an ignored local profile and runs read-only
 echo version checks for embedded Python, pip packages, FFmpeg,
 echo NVIDIA status, and bundled CUDA DLL files.
echo.
echo It will NOT run DeepFaceLab main.py or start training.
echo.

set "RUNTIME_ROOT=F:\DFL-Legacy\DFL_NVIDIA_RTX3000_20211120\DeepFaceLab_NVIDIA_RTX3000_series"
set "PROFILE=config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1"

if not exist "%RUNTIME_ROOT%\_internal\python-3.6.8\python.exe" (
    echo ERROR: Embedded Python was not found under:
    echo %RUNTIME_ROOT%
    echo.
    pause
    exit /b 1
)

if not exist "%RUNTIME_ROOT%\_internal\ffmpeg\ffmpeg.exe" (
    echo ERROR: Embedded FFmpeg was not found under:
    echo %RUNTIME_ROOT%
    echo.
    pause
    exit /b 1
)

echo Runtime root:
echo %RUNTIME_ROOT%
echo.
echo Local profile:
echo %PROFILE%
echo.
set /p "CONFIRM=Type PROBE to continue: "
if /i not "%CONFIRM%"=="PROBE" (
    echo.
    echo Cancelled.
    echo.
    pause
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\configure-and-probe-legacy-runtime.ps1" -RuntimeRoot "%RUNTIME_ROOT%" -ProfilePath "%PROFILE%" -MachineId "hp-a2000" -EnvironmentId "legacy-dfl-rtx3000-20211120"

if errorlevel 1 (
    echo.
    echo ERROR: The read-only runtime probe did not pass.
    echo Copy the error shown above into the development chat.
    echo.
    pause
    exit /b 1
)

echo.
echo Read-only probe completed. DeepFaceLab main.py was not run.
echo Copy the generated JSON report into the development chat.
echo.
pause
exit /b 0
