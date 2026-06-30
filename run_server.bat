@echo off
setlocal enabledelayedexpansion
echo ------------------------------------------
echo OLTogether - Server
echo ------------------------------------------

cd /d "%~dp0"
CALL _load_config.cmd
if errorlevel 1 exit /b 1

set PY=python
where python >nul 2>&1
if errorlevel 1 (
    where py >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Python not found. Install Python or add it to PATH.
        pause
        exit /b 1
    )
    set PY=py
)

echo [1/2] Killing old processes...
taskkill /F /IM OLGame.exe >nul 2>&1
taskkill /F /IM python.exe >nul 2>&1
taskkill /F /IM py.exe     >nul 2>&1
timeout /t 1 /nobreak >nul

echo [2/2] Starting TCP relay server...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%PY%' -ArgumentList '%~dp0%BRIDGE_SCRIPT%'"
timeout /t 2 /nobreak >nul

echo.
echo Server launched. Close the server window to shut down.
pause
exit /b 0