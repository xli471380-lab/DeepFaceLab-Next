@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Controlled TensorFlow and GPU visibility probe

echo.
echo ============================================================
echo   DeepFaceLab-Next - Controlled TensorFlow/GPU visibility
echo ============================================================
echo.
echo This step imports TensorFlow and enumerates GPU devices only.
echo It will NOT execute DeepFaceLab main.py, bundled launcher BAT
echo files, extraction, model creation, tensor workloads, training,
echo merge, or DFM export.
echo.
echo Safety controls:
echo - requires a passed step 9 schema v4 report
echo - removes system CUDA/CUDNN environment paths from the child
echo - uses only discovered historical runtime DLL directories
echo - stops the isolated process tree after 180 seconds
echo - captures stdout, stderr, stage progress, and a JSON report
echo - compares the workspace before and after the probe
echo.

set "PROFILE=config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1"
if not "%~1"=="" set "PROFILE=%~1"

if not exist "%PROFILE%" (
    echo ERROR: Local historical runtime profile was not found:
    echo %PROFILE%
    echo.
    echo Run steps 7 through 9 first.
    echo.
    pause
    exit /b 1
)

echo Local profile:
echo %PROFILE%
echo.
echo Before continuing, the entire extracted runtime folder must have
echo been scanned by the active antivirus with zero risks found.
echo Do not add exclusions or restore quarantined files.
echo.
set /p "CONFIRM=Type SCAN0-TFPROBE to confirm the zero-risk scan and continue: "
if /i not "%CONFIRM%"=="SCAN0-TFPROBE" (
    echo.
    echo Cancelled. TensorFlow was not imported.
    echo.
    pause
    exit /b 2
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\run-legacy-tensorflow-gpu-probe-v2.ps1" -ProfilePath "%PROFILE%" -AntivirusScanConfirmed -TimeoutSeconds 180

if errorlevel 1 (
    echo.
    echo TensorFlow/GPU visibility was not accepted.
    echo This may be an expected compatibility result, not script damage.
    echo Copy the status, report path, and stderr tail into the development chat.
    echo Do NOT start extraction or training yet.
    echo.
    pause
    exit /b 1
)

echo.
echo Controlled TensorFlow/GPU visibility probe passed.
echo DeepFaceLab main.py and training were not started.
echo Copy the generated report summary into the development chat.
echo.
pause
exit /b 0
