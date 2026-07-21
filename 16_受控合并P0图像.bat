@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"

set "PROFILE=%~1"
set "WORKSPACE=%~2"

if not defined PROFILE set "PROFILE=config\local\rtx5880-ada-legacy-dfl-rtx3000-20211120.psd1"
if not defined WORKSPACE set /p "WORKSPACE=Enter isolated P0 workspace path: "

echo.
echo ============================================================
echo   DeepFaceLab-Next - P0 controlled merge gate
echo ============================================================
echo.
echo This step loads the accepted iteration-4 SAEHD checkpoint and
echo merges the three authorized synthetic destination images.
echo.
echo Fixed merge boundary:
echo - existing model: p0gate_SAEHD
echo - required iteration: 4
echo - destination inputs: exactly 3 images
echo - aligned destination faces: exactly 3
echo - non-interactive merger
echo - mode: overlay
echo - mask mode: dst
echo - color transfer: rct
echo - workers: 1
echo - GPU index: 0
echo - timeout: 600 seconds
echo.
echo Safety controls:
echo - requires the passed step-15 workspace marker
echo - requires final merged and merged-mask directories to be empty
echo - writes only to new temporary output directories first
echo - validates file sets, hashes, dimensions, and nonzero masks
echo - verifies the iteration-4 checkpoint remains unchanged
echo - checks destination inputs, aligned faces, historical workspace, and Git
echo - commits both output directories only after all checks pass
echo - removes temporary output when blocked
echo.
echo It will execute DeepFaceLab main.py, TensorFlow inference, and merger workers.
echo It will NOT train, resume training, export a DFM, or modify the historical workspace.
echo.
echo Local profile:
echo %PROFILE%
echo.
echo Isolated P0 workspace:
echo %WORKSPACE%
echo.
echo Confirm all of the following:
echo - the workspace contains only the authorized synthetic P0 identities
echo - the iteration-4 checkpoint is the accepted disposable P0 model
echo - creating three local merged test images and masks is intended
echo - training and DFM export are NOT intended in this step
echo.
set /p "CONFIRM=Type MERGE-P0-IMAGES to continue: "

if /i not "%CONFIRM%"=="MERGE-P0-IMAGES" (
    echo.
    echo Confirmation did not match. Nothing was executed.
    pause
    exit /b 1
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\run-p0-controlled-merge-gate.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%WORKSPACE%" -MergeConfirmed
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Controlled P0 merge gate passed.
    echo Three merged images and three masks were committed locally.
    echo Visually review both output directories before DFM export.
    echo Copy the generated summary into the development chat.
) else (
    echo Controlled P0 merge gate was blocked.
    echo Copy the status, report path, validation result, and stderr tails into the development chat.
    echo Do NOT manually merge again or export a DFM.
)

echo.
pause
exit /b %RC%
