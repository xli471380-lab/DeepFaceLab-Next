@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - Legacy Runtime Discovery

echo.
echo ============================================================
echo   DeepFaceLab-Next - Legacy Runtime Discovery
echo ============================================================
echo.
echo Notes:
echo - Reads directory metadata and version information only.
echo - Does not run discovered BAT files.
echo - Does not install or modify Python, CUDA, or FFmpeg.
echo - Saves the report under artifacts.
echo.

set "PROFILE="
for /f "delims=" %%P in ('dir /b /a-d "config\local\*.psd1" 2^>nul') do if not defined PROFILE set "PROFILE=config\local\%%P"

if defined PROFILE (
    echo Local profile: %PROFILE%
) else (
    echo No local profile found under config\local.
    echo The Windows computer name will be used as the report label.
)
echo.

set "ROOTS="
set /p "ROOTS=Search roots, separated by commas. Press Enter or type ALL for all fixed drives: "
if /i "%ROOTS%"=="ALL" set "ROOTS="

echo.
echo Scanning. Large drives may take several minutes...
echo.

if defined ROOTS (
    set "DFL_SEARCH_ROOTS=%ROOTS%"
    if defined PROFILE (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
          "$items = New-Object 'System.Collections.Generic.List[string]'; foreach ($item in $env:DFL_SEARCH_ROOTS.Split(',')) { $value = $item.Trim(); if ($value) { [void]$items.Add($value) } }; & '.\scripts\windows\discover-legacy-runtime.ps1' -ProfilePath '%PROFILE%' -SearchRoots $items.ToArray() -MaxDepth 4"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
          "$items = New-Object 'System.Collections.Generic.List[string]'; foreach ($item in $env:DFL_SEARCH_ROOTS.Split(',')) { $value = $item.Trim(); if ($value) { [void]$items.Add($value) } }; & '.\scripts\windows\discover-legacy-runtime.ps1' -SearchRoots $items.ToArray() -MaxDepth 4"
    )
    set "DFL_SEARCH_ROOTS="
) else (
    if defined PROFILE (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\discover-legacy-runtime.ps1" -ProfilePath "%PROFILE%" -MaxDepth 4
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\discover-legacy-runtime.ps1" -MaxDepth 4
    )
)

if errorlevel 1 (
    echo.
    echo Discovery failed. Share the error output with the developer.
    echo.
    pause
    exit /b 1
)

echo.
echo Discovery completed. Share the latest JSON report with the developer.
echo.
pause
exit /b 0
