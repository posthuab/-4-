@echo off
setlocal
title Xbox Live / Forza Horizon 4 Online Fix

rem Self-elevate if not already running as administrator.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo   Xbox Live / Forza Horizon 4 Online Fix
echo   --------------------------------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-XboxLive.ps1" %*

echo.
echo   Finished. Press any key to close.
pause >nul
