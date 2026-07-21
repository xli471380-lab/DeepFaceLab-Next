@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0"

set "PYTHON_EXE=%~1"
if not defined PYTHON_EXE set "PYTHON_EXE=python.exe"

echo.
echo ============================================================
echo   DeepFaceLab-Next - P1 repository privacy gate
echo ============================================================
echo.
echo This is a CPU-only static validation step.
echo It does not start DeepFaceLab, TensorFlow, training, merge,
echo DFM export, VisoMaster Fusion, or any other GPU workload.
echo.
echo It checks only Git-tracked paths and basic file metadata for:
echo - local profiles and generated artifact directories
echo - workspace, media, checkpoint, model, DFM, and archive files
echo - credential-like filenames
echo - oversized non-text files
echo.
echo Python:
echo %PYTHON_EXE%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\run-p1-repository-privacy-gate.ps1" -PythonExe "%PYTHON_EXE%" -RepoRoot "%~dp0"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo P1 repository privacy and boundary gate passed.
) else (
    echo P1 repository privacy and boundary gate did not pass.
    echo Review the printed failure code and ignored report under .p1-local.
)

echo.
pause
exit /b %RC%
