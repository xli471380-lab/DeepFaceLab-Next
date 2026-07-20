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
echo   DeepFaceLab-Next - P0 initial SAEHD training/save gate
echo ============================================================
echo.
echo This step creates one NEW disposable SAEHD checkpoint in the
echo isolated authorized synthetic workspace.
echo.
echo Fixed training boundary:
echo - model: SAEHD
echo - resolution: 96
echo - face type: whole_face
echo - architecture: df
echo - batch size: 2
echo - GPU index: 0
echo - target iteration: 2
echo - no preview window
echo - graceful save and exit after iteration 2
echo - overall timeout: 900 seconds
echo.
echo Safety controls:
echo - requires the passed step-13 extraction marker
echo - requires your visual review of all six aligned faces
echo - requires the final model directory to be empty
echo - writes to a temporary model directory first
echo - validates checkpoint files, options, iteration, and losses
echo - checks aligned hashes, historical workspace, and Git status
echo - removes only generated temporary model output if blocked
echo.
echo It will execute DeepFaceLab main.py and TensorFlow training.
echo It will NOT resume training, merge images, or export a DFM.
echo.
echo Local profile:
echo %PROFILE%
echo.
echo Isolated P0 workspace:
echo %WORKSPACE%
echo.
echo Confirm all of the following:
echo - the six aligned synthetic faces were visually reviewed
echo - none is blank, inverted, severely cropped, or misdetected
echo - creating a disposable two-iteration SAEHD checkpoint is intended
echo - resume, merge, and DFM export are NOT intended in this step
echo.
set /p "CONFIRM=Type VISUAL-REVIEW-PASSED to continue: "

if /i not "%CONFIRM%"=="VISUAL-REVIEW-PASSED" (
    echo.
    echo Confirmation did not match. Nothing was executed.
    pause
    exit /b 1
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\run-p0-initial-training-save-gate.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%WORKSPACE%" -VisualReviewConfirmed
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Controlled P0 initial training and save gate passed.
    echo A two-iteration SAEHD checkpoint was saved. Resume was not started.
    echo Copy the generated summary into the development chat.
) else (
    echo Controlled P0 initial training and save gate was blocked.
    echo Copy the status, report path, and stderr tails into the development chat.
    echo Do NOT manually start training, merge, or DFM export.
)

pause
exit /b %RC%
