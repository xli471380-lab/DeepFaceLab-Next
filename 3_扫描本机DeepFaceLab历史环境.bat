@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"
title DeepFaceLab-Next - 扫描本机历史运行环境

echo.
echo ============================================================
echo   DeepFaceLab-Next - 扫描本机 DeepFaceLab 历史运行环境
echo ============================================================
echo.
echo 说明：
echo - 只读取目录和版本信息
echo - 不运行发现的 BAT 文件
echo - 不安装或修改 Python、CUDA、FFmpeg
echo - 扫描报告保存在 artifacts 目录
echo.

set "PROFILE="
for /f "delims=" %%P in ('dir /b /a-d "config\local\*.psd1" 2^>nul') do if not defined PROFILE set "PROFILE=config\local\%%P"

if defined PROFILE (
    echo 使用本机环境档案：%PROFILE%
) else (
    echo [提示] config\local 中没有找到本机环境档案。
    echo 将使用 Windows 电脑名称作为报告标签。
)
echo.

set "ROOTS="
set /p "ROOTS=输入要扫描的盘符或目录，多个路径用英文逗号分隔；直接回车扫描全部固定磁盘："

echo.
echo 正在扫描，请等待。大型磁盘可能需要几分钟...
echo.

if defined ROOTS (
    if defined PROFILE (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
          "$items = '%ROOTS%'.Split(',') ^| ForEach-Object { $_.Trim() } ^| Where-Object { $_ };" ^
          "& '.\scripts\windows\discover-legacy-runtime.ps1' -ProfilePath '%PROFILE%' -SearchRoots $items -MaxDepth 4"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
          "$items = '%ROOTS%'.Split(',') ^| ForEach-Object { $_.Trim() } ^| Where-Object { $_ };" ^
          "& '.\scripts\windows\discover-legacy-runtime.ps1' -SearchRoots $items -MaxDepth 4"
    )
) else (
    if defined PROFILE (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\discover-legacy-runtime.ps1" -ProfilePath "%PROFILE%" -MaxDepth 4
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\discover-legacy-runtime.ps1" -MaxDepth 4
    )
)

if errorlevel 1 (
    echo.
    echo [错误] 扫描没有完成，请把上面的错误信息发给开发助手。
    echo.
    pause
    exit /b 1
)

echo.
echo 扫描完成。请把最后显示的 JSON 报告内容发给开发助手。
echo.
pause
exit /b 0
