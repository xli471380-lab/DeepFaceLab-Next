@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title DeepFaceLab-Next - P0 authorized dataset preflight

echo.
echo ============================================================
echo   DeepFaceLab-Next - P0 authorized dataset preflight
echo ============================================================
echo.
echo This step records hashes and read-only media metadata only.
echo It will NOT copy media, extract frames or faces, import
echo TensorFlow, execute DeepFaceLab, or start training.
echo.
echo Required safety boundary:
echo - source and destination must be different authorized identities
echo - media must remain local, non-public, and outside this repository
echo - media must remain outside the historical runtime and workspace
echo - public figures and unconsented third-party identities are not allowed
echo.

set "PROFILE=config\local\hp-a2000-legacy-dfl-rtx3000-20211120.psd1"
if not "%~1"=="" set "PROFILE=%~1"

set "SOURCE_MEDIA=%~2"
set "DESTINATION_MEDIA=%~3"

if not exist "%PROFILE%" (
    echo ERROR: Local historical runtime profile was not found:
    echo %PROFILE%
    echo.
    echo Run steps 7 through 10 first.
    echo.
    pause
    exit /b 1
)

if "%SOURCE_MEDIA%"=="" (
    set /p "SOURCE_MEDIA=Enter the full source-identity media file or folder path: "
)
if "%DESTINATION_MEDIA%"=="" (
    set /p "DESTINATION_MEDIA=Enter the full destination-identity media file or folder path: "
)

if "%SOURCE_MEDIA%"=="" (
    echo ERROR: Source media path is empty.
    pause
    exit /b 1
)
if "%DESTINATION_MEDIA%"=="" (
    echo ERROR: Destination media path is empty.
    pause
    exit /b 1
)
if not exist "%SOURCE_MEDIA%" (
    echo ERROR: Source media path does not exist:
    echo %SOURCE_MEDIA%
    pause
    exit /b 1
)
if not exist "%DESTINATION_MEDIA%" (
    echo ERROR: Destination media path does not exist:
    echo %DESTINATION_MEDIA%
    pause
    exit /b 1
)

echo.
echo Local profile:
echo %PROFILE%
echo.
echo Source identity media:
echo %SOURCE_MEDIA%
echo.
echo Destination identity media:
echo %DESTINATION_MEDIA%
echo.
echo Confirm all of the following:
echo - both subjects are adults or otherwise lawfully authorized
echo - you own or have permission to process both media sets
echo - source and destination are different identities
echo - neither set contains a public figure or unconsented third party
echo - the files will remain local and will not be committed to Git
echo.
set /p "CONFIRM=Type AUTHORIZED-P0-DATASET to continue: "
if /i not "%CONFIRM%"=="AUTHORIZED-P0-DATASET" (
    echo.
    echo Cancelled. No media was read or copied.
    echo.
    pause
    exit /b 2
)

echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\windows\create-p0-authorized-dataset-manifest.ps1" -ProfilePath "%PROFILE%" -SourceMediaPath "%SOURCE_MEDIA%" -DestinationMediaPath "%DESTINATION_MEDIA%" -AuthorizationConfirmed

if errorlevel 1 (
    echo.
    echo Dataset preflight did not pass.
    echo Copy the error and any generated manifest path into the development chat.
    echo Do NOT copy media into workspace or start extraction.
    echo.
    pause
    exit /b 1
)

echo.
echo P0 authorized dataset preflight passed.
echo No media was copied and DeepFaceLab was not started.
echo Copy the generated manifest summary into the development chat.
echo.
pause
exit /b 0
