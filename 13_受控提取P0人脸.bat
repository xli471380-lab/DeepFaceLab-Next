@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Controlled P0 face extraction

echo.
echo ============================================================
echo   DeepFaceLab-Next - Controlled P0 face extraction
echo ============================================================
echo.
echo This step runs S3FD face detection and whole-face alignment on
echo the isolated authorized synthetic P0 workspace only.
echo.
echo Fixed parameters:
echo - detector: S3FD
echo - face type: whole_face
echo - maximum faces per image: 1
echo - aligned size: 512
echo - JPEG quality: 90
echo - GPU index: 0
echo - timeout: 300 seconds for source and 300 seconds for destination
echo.
echo Safety controls:
echo - requires passed step 10 and step 12 reports
echo - verifies every copied input SHA-256 before and after extraction
echo - requires both aligned directories to be empty
echo - writes each role to a new temporary directory first
echo - validates every DFLJPG metadata record before committing output
echo - cleans only temporary output when extraction is blocked
echo - checks the historical default workspace and Git repository
echo.
echo It will execute DeepFaceLab main.py for extraction and import
echo TensorFlow. It will NOT create a model, start training, merge,
echo export DFM, or modify the historical default workspace.
echo.

set "PROFILE=config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1"
if not "%~1"=="" set "PROFILE=%~1"

set "WORKSPACE=D:\DFL-P0-Authorized\workspace-p0"
if not "%~2"=="" set "WORKSPACE=%~2"

if not exist "%PROFILE%" (
    echo ERROR: Local historical runtime profile was not found:
    echo %PROFILE%
    echo.
    pause
    exit /b 1
)

if not exist "%WORKSPACE%\p0-workspace-manifest.json" (
    echo ERROR: Prepared P0 workspace marker was not found:
    echo %WORKSPACE%\p0-workspace-manifest.json
    echo.
    echo Run and pass step 12 first.
    echo.
    pause
    exit /b 1
)

echo Local profile:
echo %PROFILE%
echo.
echo Isolated P0 workspace:
echo %WORKSPACE%
echo.
echo Confirm all of the following:
echo - this workspace contains only the authorized synthetic P0 identities
echo - source and destination aligned directories are empty
echo - running face detection and alignment on these six images is intended
echo - no model creation, training, merge, or export is intended yet
echo.
set /p "CONFIRM=Type EXTRACT-P0-FACES to continue: "
if /i not "%CONFIRM%"=="EXTRACT-P0-FACES" (
    echo.
    echo Cancelled. DeepFaceLab and TensorFlow were not started.
    echo.
    pause
    exit /b 2
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\run-p0-controlled-face-extraction.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%WORKSPACE%" -ExtractConfirmed -TimeoutSecondsPerRole 300

if errorlevel 1 (
    echo.
    echo Controlled P0 face extraction was not accepted.
    echo Copy the status, report path, and stderr tails into the development chat.
    echo Do NOT start training or manually rerun historical extraction BAT files.
    echo.
    pause
    exit /b 1
)

echo.
echo Controlled P0 face extraction passed.
echo No model, training, merge, or DFM export was started.
echo Copy the generated summary into the development chat.
echo.
pause
exit /b 0
