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
echo   DeepFaceLab-Next - P0 controlled DFM export gate
echo ============================================================
echo.
echo This step exports one DFM from the accepted iteration-4 SAEHD
echo checkpoint after the three merged images and masks passed review.
echo.
echo Fixed export boundary:
echo - existing model: p0gate_SAEHD
echo - required iteration: 4
echo - historical official export mode: CPU-only
echo - expected output: p0gate_SAEHD_model.dfm
echo - ONNX opset: 12
echo - timeout: 900 seconds
echo.
echo Safety controls:
echo - requires passed step-15 and step-16 workspace markers
echo - records that the merged images and masks passed visual review
echo - clones all eight checkpoint files and verifies SHA-256 first
echo - exports only from the temporary checkpoint clone
echo - validates ONNX structure, tensor names, opset, size, and hash
echo - requires the cloned and formal checkpoints to remain unchanged
echo - commits only one validated DFM into workspace-p0\dfm
echo - removes temporary or partial DFM output when blocked
echo.
echo It will execute TensorFlow graph freezing and tf2onnx conversion.
echo It will NOT train, resume training, merge images, or open VisoMaster.
echo.
echo Local profile:
echo %PROFILE%
echo.
echo Isolated P0 workspace:
echo %WORKSPACE%
echo.
echo Confirm all of the following:
echo - the three merged images and masks were visually reviewed and accepted
echo - the iteration-4 checkpoint is the accepted disposable P0 model
echo - creating one local DFM for compatibility testing is intended
echo - only authorized synthetic P0 identities are present
echo.
set /p "CONFIRM=Type EXPORT-P0-DFM to continue: "

if /i not "%CONFIRM%"=="EXPORT-P0-DFM" (
    echo.
    echo Confirmation did not match. Nothing was executed.
    pause
    exit /b 1
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\run-p0-controlled-dfm-export-gate.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%WORKSPACE%" -ExportConfirmed -VisualReviewConfirmed
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Controlled P0 DFM export gate passed.
    echo One validated DFM was committed locally under workspace-p0\dfm.
    echo Copy the generated summary into the development chat before VisoMaster testing.
) else (
    echo Controlled P0 DFM export gate was blocked.
    echo Copy the status, report path, export result, validation result, and stderr tails into the development chat.
    echo Do NOT manually export again or load a partial DFM.
)

echo.
pause
exit /b %RC%
