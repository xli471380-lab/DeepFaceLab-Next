@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"

set "PROFILE=%~1"
set "WORKSPACE=%~2"
set "FUSION_ROOT=%~3"

if not defined PROFILE set "PROFILE=config\local\rtx5880-ada-legacy-dfl-rtx3000-20211120.psd1"
if not defined WORKSPACE set "WORKSPACE=D:\DFL-P0-Authorized\workspace-p0"
if not defined FUSION_ROOT set "FUSION_ROOT=E:\SECourses\VisoMaster-Fusion\VisoMaster-Fusion"

echo.
echo ============================================================
echo   DeepFaceLab-Next - P0 VisoMaster Fusion acceptance record
echo ============================================================
echo.
echo This step records the already-observed P0 Gate F result.
echo It does not start VisoMaster Fusion or run inference again.
echo.
echo Required observed result:
echo - DeepFaceLive (DFM) was selected
echo - p0gate_SAEHD_model.dfm appeared in the DFM Model list
echo - one authorized synthetic target image was loaded
echo - one target face was detected
echo - Swap Faces executed one DFM inference
echo - the preview visibly changed
echo - the application remained open and responsive
echo - no blocking CUDA, TensorRT, provider, tensor-name, or shape error occurred
echo.
echo Integrity checks performed by this recorder:
echo - requires the passed step-17 export manifest
echo - re-hashes the workspace DFM
echo - re-hashes the VisoMaster Fusion DFM copy
echo - requires both files to match exactly
echo - records the VisoMaster Git branch and commit
echo - requires the DeepFaceLab-Next Git working tree to remain clean
echo - writes only ignored artifacts and a local workspace marker
echo.
echo This record makes no visual-quality claim. The four-iteration model
echo is accepted only for pipeline compatibility and reproducibility.
echo.
echo Local profile:
echo %PROFILE%
echo.
echo Isolated P0 workspace:
echo %WORKSPACE%
echo.
echo VisoMaster Fusion repository:
echo %FUSION_ROOT%
echo.
set /p "CONFIRM=Type ACCEPT-P0-VISOMASTER to record the observed result: "

if /i not "%CONFIRM%"=="ACCEPT-P0-VISOMASTER" (
    echo.
    echo Confirmation did not match. Nothing was recorded.
    pause
    exit /b 1
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\record-p0-visomaster-fusion-acceptance.ps1" -ProfilePath "%PROFILE%" -WorkspaceRoot "%WORKSPACE%" -FusionRoot "%FUSION_ROOT%" -AcceptanceConfirmed -DfmListedConfirmed -ImageLoadedConfirmed -FaceDetectedConfirmed -InferenceExecutedConfirmed -PreviewChangedConfirmed -ApplicationStableConfirmed -NoBlockingProviderErrorsConfirmed
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo P0 VisoMaster Fusion acceptance record passed.
    echo P0 Gate F now has a machine-readable local report and workspace marker.
    echo Copy the generated summary into the development chat.
) else (
    echo P0 VisoMaster Fusion acceptance recording was blocked.
    echo Copy the complete error and terminal output into the development chat.
    echo Do not delete or recreate the DFM.
)

echo.
pause
exit /b %RC%
