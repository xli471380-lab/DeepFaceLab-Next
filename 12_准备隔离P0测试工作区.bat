@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Prepare isolated P0 workspace

echo.
echo ============================================================
echo   DeepFaceLab-Next - Prepare isolated P0 test workspace
echo ============================================================
echo.
echo This step verifies the passed step-11 manifest and all input
echo SHA-256 hashes, then copies the authorized synthetic images to
echo a NEW isolated workspace outside the historical runtime.
echo.
echo It will NOT execute DeepFaceLab main.py, import TensorFlow,
echo extract faces, create a model, or start training.
echo.
echo Safety controls:
echo - the target workspace must not already exist
echo - no existing files or directories are overwritten
echo - source media is read and copied, never modified
echo - the historical default workspace is checked before and after
echo - the Git working tree must remain unchanged
echo - failed preparation removes only its temporary staging folder
echo.

set "PROFILE=config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1"
if not "%~1"=="" set "PROFILE=%~1"

set "TARGET=D:\DFL-P0-Authorized\workspace-p0"
if not "%~2"=="" set "TARGET=%~2"

set "MANIFEST="
if not "%~3"=="" set "MANIFEST=%~3"

if not exist "%PROFILE%" (
    echo ERROR: Local historical runtime profile was not found:
    echo %PROFILE%
    echo.
    pause
    exit /b 1
)

if exist "%TARGET%" (
    echo ERROR: The isolated workspace target already exists.
    echo Nothing will be overwritten or deleted:
    echo %TARGET%
    echo.
    echo Choose a new path or manually inspect and move the existing folder.
    echo.
    pause
    exit /b 1
)

echo Local profile:
echo %PROFILE%
echo.
echo New isolated workspace:
echo %TARGET%
echo.
if not "%MANIFEST%"=="" (
    echo Dataset manifest:
    echo %MANIFEST%
    echo.
) else (
    echo Dataset manifest:
    echo latest passed step-11 manifest for this profile
    echo.
)

echo Confirm all of the following:
echo - the step-11 source and destination identities remain authorized
echo - this target path is disposable and does not already contain data
echo - copying the six synthetic test images is intended
echo - extraction and training will NOT start in this step
echo.
set /p "CONFIRM=Type PREPARE-P0-WORKSPACE to continue: "
if /i not "%CONFIRM%"=="PREPARE-P0-WORKSPACE" (
    echo.
    echo Cancelled. No isolated workspace was created.
    echo.
    pause
    exit /b 2
)

echo.
if "%MANIFEST%"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\prepare-p0-isolated-workspace.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%TARGET%" -PrepareConfirmed
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\prepare-p0-isolated-workspace.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%TARGET%" -DatasetManifestPath "%MANIFEST%" -PrepareConfirmed
)

if errorlevel 1 (
    echo.
    echo Isolated P0 workspace preparation did not pass.
    echo No extraction or training was started.
    echo Copy the error and report path into the development chat.
    echo.
    pause
    exit /b 1
)

echo.
echo Isolated P0 workspace preparation passed.
echo No faces were extracted and no training was started.
echo Copy the generated summary into the development chat.
echo.
pause
exit /b 0
