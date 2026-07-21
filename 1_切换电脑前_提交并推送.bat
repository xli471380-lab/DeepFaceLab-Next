@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"
title DeepFaceLab-Next - 切换电脑前提交并推送

echo.
echo ============================================================
echo   DeepFaceLab-Next - 切换电脑前：提交并推送
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

set "BRANCH="
for /f "delims=" %%B in ('git branch --show-current') do set "BRANCH=%%B"
if not defined BRANCH (
    echo [错误] 当前处于 detached HEAD，不能自动推送。
    echo 请先执行 git switch ^<分支名^>。
    goto :fail
)

echo 当前目录：%CD%
echo 当前分支：%BRANCH%
echo.

echo [1/5] 获取远程分支信息...
git fetch origin --prune
if errorlevel 1 (
    echo [错误] git fetch 失败，请检查网络和 GitHub 登录状态。
    goto :fail
)

echo.
echo [2/5] 检查本地改动...
set "STATUS_FILE=%TEMP%\dflnext_status_%RANDOM%_%RANDOM%.txt"
git status --porcelain > "%STATUS_FILE%"
for %%F in ("%STATUS_FILE%") do set "STATUS_SIZE=%%~zF"

if "%STATUS_SIZE%"=="0" (
    echo 工作区干净，没有需要提交的文件。
    del "%STATUS_FILE%" >nul 2>nul
    goto :sync_remote
)

echo 检测到以下未提交改动：
type "%STATUS_FILE%"
del "%STATUS_FILE%" >nul 2>nul

echo.
set "COMMIT_MSG="
set /p "COMMIT_MSG=请输入本次提交说明（留空则取消）："
if not defined COMMIT_MSG (
    echo 已取消，没有提交或推送任何改动。
    goto :cancel
)

echo.
echo [3/5] 暂存改动并等待确认...
git add -A
if errorlevel 1 (
    echo [错误] git add 失败。
    goto :fail
)

echo.
echo 即将提交的文件：
git status --short

echo.
set "CONFIRM="
set /p "CONFIRM=确认这些文件都可以提交吗？输入 Y 继续，其他键取消："
if /i not "%CONFIRM%"=="Y" (
    echo 正在取消暂存，文件内容不会丢失...
    git reset >nul 2>nul
    goto :cancel
)

git diff --cached --quiet
if not errorlevel 1 (
    echo 没有可提交的已暂存改动，跳过提交。
    goto :sync_remote
)

echo.
echo [4/5] 创建本地提交...
git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
    echo [错误] git commit 失败。请检查上面的提示。
    goto :fail
)

:sync_remote
echo.
echo [5/5] 同步远程并推送当前分支...
git show-ref --verify --quiet "refs/remotes/origin/%BRANCH%"
if not errorlevel 1 (
    git pull --rebase origin "%BRANCH%"
    if errorlevel 1 (
        echo.
        echo [错误] 拉取或 rebase 失败，可能存在冲突。
        echo 请解决冲突后执行：git rebase --continue
        echo 需要放弃本次 rebase 时执行：git rebase --abort
        goto :fail
    )
) else (
    echo 远程还没有分支 %BRANCH%，将创建远程分支。
)

git push -u origin "%BRANCH%"
if errorlevel 1 (
    echo [错误] git push 失败，请检查网络、权限或登录状态。
    goto :fail
)

echo.
echo ============================================================
echo   完成：当前分支已经同步到 GitHub
echo ============================================================
echo 当前分支：%BRANCH%
for /f "delims=" %%C in ('git rev-parse HEAD') do echo 当前提交：%%C
echo.
git status --short --branch
echo.
pause
exit /b 0

:cancel
echo.
echo 操作已取消。
echo.
pause
exit /b 2

:fail
echo.
echo 操作未完成，请根据上面的错误信息处理。
echo.
pause
exit /b 1
