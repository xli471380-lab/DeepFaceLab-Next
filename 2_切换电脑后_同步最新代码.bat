@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"
title DeepFaceLab-Next - 切换电脑后同步最新代码

echo.
echo ============================================================
echo   DeepFaceLab-Next - 切换电脑后：同步最新代码
echo ============================================================
echo.

where git >nul 2>nul
if errorlevel 1 (
    echo [错误] 没有找到 Git，请先确认 Git 已安装并加入 PATH。
    goto :fail
)

git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    echo [错误] 当前目录不是 Git 仓库：%CD%
    goto :fail
)

echo [1/5] 检查当前工作区...
set "STATUS_FILE=%TEMP%\dflnext_status_%RANDOM%_%RANDOM%.txt"
git status --porcelain > "%STATUS_FILE%"
for %%F in ("%STATUS_FILE%") do set "STATUS_SIZE=%%~zF"

if not "%STATUS_SIZE%"=="0" (
    echo.
    echo [阻止同步] 当前电脑存在未提交改动：
    type "%STATUS_FILE%"
    del "%STATUS_FILE%" >nul 2>nul
    echo.
    echo 请先处理这些改动。不要直接拉取，以免覆盖或混合两台电脑的工作。
    echo 可先运行：1_切换电脑前_提交并推送.bat
    goto :fail
)
del "%STATUS_FILE%" >nul 2>nul

echo 工作区干净，可以安全同步。
echo.

echo [2/5] 获取 GitHub 最新分支信息...
git fetch origin --prune
if errorlevel 1 (
    echo [错误] git fetch 失败，请检查网络和 GitHub 登录状态。
    goto :fail
)

set "CURRENT_BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do set "CURRENT_BRANCH=%%B"

set "TARGET_BRANCH=%~1"
if not defined TARGET_BRANCH (
    if defined CURRENT_BRANCH (
        echo 当前本地分支：%CURRENT_BRANCH%
        set /p "TARGET_BRANCH=请输入要同步的分支，直接回车使用当前分支："
        if not defined TARGET_BRANCH set "TARGET_BRANCH=%CURRENT_BRANCH%"
    ) else (
        set /p "TARGET_BRANCH=请输入要同步的远程分支名："
    )
)

if not defined TARGET_BRANCH (
    echo [错误] 没有指定分支。
    goto :fail
)

echo.
echo 目标分支：%TARGET_BRANCH%
echo.

echo [3/5] 检查远程分支是否存在...
git show-ref --verify --quiet "refs/remotes/origin/%TARGET_BRANCH%"
if errorlevel 1 (
    echo [错误] GitHub 上没有找到分支：origin/%TARGET_BRANCH%
    echo 可执行 git branch -r 查看远程分支。
    goto :fail
)

echo [4/5] 切换到目标分支...
git show-ref --verify --quiet "refs/heads/%TARGET_BRANCH%"
if errorlevel 1 (
    git switch --track -c "%TARGET_BRANCH%" "origin/%TARGET_BRANCH%"
) else (
    git switch "%TARGET_BRANCH%"
)
if errorlevel 1 (
    echo [错误] 无法切换到分支 %TARGET_BRANCH%。
    goto :fail
)

echo.
echo [5/5] 快进拉取最新代码...
git pull --ff-only origin "%TARGET_BRANCH%"
if errorlevel 1 (
    echo.
    echo [错误] 无法进行 fast-forward 拉取。
    echo 本地分支可能有未推送提交，或远程历史已发生分叉。
    echo 请先运行 git status 和 git log --oneline --decorate -10 检查，不要强制覆盖。
    goto :fail
)

echo.
echo ============================================================
echo   完成：当前电脑已同步 GitHub 最新代码
echo ============================================================
echo 当前分支：%TARGET_BRANCH%
for /f "delims=" %%C in ('git rev-parse HEAD') do echo 当前提交：%%C
echo.
git status --short --branch
echo.
pause
exit /b 0

:fail
echo.
echo 操作未完成，请根据上面的提示处理。
echo.
pause
exit /b 1
