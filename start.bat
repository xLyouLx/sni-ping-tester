@echo off
chcp 1251 >nul
title SNI Tester

set "GITURL=https://github.com/hxehex/russia-mobile-internet-whitelist/blob/main/whitelist.txt"

if not exist "SNITEST.ps1" (
    echo.
    PowerShell -Command "Write-Host 'ERROR: SNI Ping Tester script not found!' -ForegroundColor Red"
    echo.
    PowerShell -Command "Write-Host 'Download the latest version from GitHub:' -ForegroundColor Yellow"
    PowerShell -Command "Write-Host '%GITURL%' -ForegroundColor Cyan"
    echo.
    choice /M "Open GitHub to download script?"
    if errorlevel 2 (
        echo Exiting.
        exit /b 1
    ) else (
        start "" "%GITURL%"
        exit /b 1
    )
)

if not exist "whitelist.txt" (
    echo.
    PowerShell -Command "Write-Host 'ERROR: whitelist.txt not found!' -ForegroundColor Red"
    echo.
    PowerShell -Command "Write-Host 'You need to download whitelist.txt from:' -ForegroundColor Yellow"
    PowerShell -Command "Write-Host '%GITURL%' -ForegroundColor Cyan"
    echo.
    choice /M "Open GitHub to download whitelist?"
    if errorlevel 2 (
        echo Exiting.
        exit /b 1
    ) else (
        start "" "%GITURL%"
        exit /b 1
    )
)

for /f "delims=" %%P in ('powershell -NoProfile -Command "Get-ExecutionPolicy"') do set "EP=%%P"
if /i "%EP%"=="Restricted" (
    echo.
    PowerShell -Command "Write-Host 'NOTE: PowerShell execution policy is Restricted' -ForegroundColor Yellow"
    PowerShell -Command "Write-Host 'Running script with -ExecutionPolicy Bypass' -ForegroundColor Yellow"
    echo.
)

echo ===============================
echo       SNI Ping Tester
echo ===============================

powershell -NoProfile -ExecutionPolicy Bypass -File "SNITEST.ps1"

echo.
echo Press any key to exit...
pause >nul