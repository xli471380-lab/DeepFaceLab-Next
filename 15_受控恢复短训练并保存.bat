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
echo   DeepFaceLab-Next - P0 controlled checkpoint resume gate v3
echo ============================================================
echo.
echo This step loads the accepted two-iteration SAEHD checkpoint,
echo resumes it for exactly two more iterations, saves it at four,
echo and validates checkpoint continuity before committing it.
echo.
echo Fixed resume boundary:
echo - existing model: p0gate_SAEHD
echo - before iteration: 2
echo - target iteration: 4
echo - additional iterations: 2
echo - all model settings preserved except target iteration
echo - GPU index: 0
echo - no preview window
echo - overall timeout: 900 seconds
echo.
echo Deterministic v3 resume method:
echo - validates and clones the accepted checkpoint first
echo - changes target_iter 2 to 4 only inside the temporary clone
echo - answers the timed override prompt with no
echo - sends zero blocking configuration answers
echo - disables only the interactive stale-stdin drain in this no-stdin run
echo - unblocks the parent if historical trainer initialization fails
echo.
echo Safety controls:
echo - requires the passed step-14 workspace marker
echo - validates the accepted checkpoint before copying it
echo - resumes only a full SHA-256-verified temporary clone
echo - preserves the first two loss-history rows exactly
echo - requires finite new losses and changed weight files
echo - checks aligned hashes, historical workspace, and Git status
echo - atomically swaps the resumed checkpoint only after acceptance
echo - preserves the iteration-2 checkpoint when blocked
echo.
echo It will execute DeepFaceLab main.py and TensorFlow training.
echo It will NOT merge images or export a DFM.
echo.
echo Local profile:
echo %PROFILE%
echo.
echo Isolated P0 workspace:
echo %WORKSPACE%
echo.
echo Confirm all of the following:
echo - the step-14 two-iteration checkpoint is disposable test data
echo - loading and advancing that same checkpoint to iteration 4 is intended
echo - no manual parameter changes, merge, or DFM export are intended
echo.
set /p "CONFIRM=Type RESUME-P0-CHECKPOINT to continue: "

if /i not "%CONFIRM%"=="RESUME-P0-CHECKPOINT" (
    echo.
    echo Confirmation did not match. Nothing was executed.
    pause
    exit /b 1
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\run-p0-resume-training-save-gate-v2.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%WORKSPACE%" -ResumeConfirmed
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Controlled P0 checkpoint resume gate v3 passed.
    echo The same SAEHD checkpoint advanced from iteration 2 to 4.
    echo Copy the generated summary into the development chat.
) else (
    echo Controlled P0 checkpoint resume gate v3 was blocked.
    echo Copy the status, report path, preparation result, and stderr tails into the development chat.
    echo Do NOT manually resume training, merge, or export DFM.
)

echo.
pause
exit /b %RC%
