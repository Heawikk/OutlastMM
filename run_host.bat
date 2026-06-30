@echo off
setlocal enabledelayedexpansion
echo ------------------------------------------
echo OLTogether - Host (Role=0)
echo ------------------------------------------

cd /d "%~dp0"
CALL _load_config.cmd
if errorlevel 1 exit /b 1

echo Starting HOST (Role=0)...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%GAME%' -ArgumentList 'Intro_Persistent?game=Multiplayer.OLTogetherGame?Role=0?QuickPlay','-log','-WINDOWED','-ResX=1920','-ResY=1080','-WinX=50','-WinY=200','-nosteam'"

echo.
echo Done!
pause
exit /b 0