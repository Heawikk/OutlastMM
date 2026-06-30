@echo off
setlocal enabledelayedexpansion
echo ------------------------------------------
echo OLTogether - Server + Host (Role=0)
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

echo [1/3] Killing old processes...
taskkill /F /IM OLGame.exe >nul 2>&1
taskkill /F /IM python.exe >nul 2>&1
taskkill /F /IM py.exe     >nul 2>&1
timeout /t 1 /nobreak >nul

echo [2/3] Starting TCP relay server...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%PY%' -ArgumentList '%~dp0%BRIDGE_SCRIPT%'"
timeout /t 2 /nobreak >nul

echo [3/3] Starting HOST (Role=0)...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%GAME%' -ArgumentList 'Intro_Persistent?game=Multiplayer.OLTogetherGame?Role=0?QuickPlay','-log','-WINDOWED','-ResX=1920','-ResY=1080','-WinX=50','-WinY=200','-nosteam'"

echo.
echo Server and host launched. Close the server window to shut down.
pause
exit /b 0