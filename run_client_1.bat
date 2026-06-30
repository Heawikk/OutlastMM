@echo off
setlocal enabledelayedexpansion
echo ------------------------------------------
echo OLTogether - Client (Role=1)
echo ------------------------------------------

cd /d "%~dp0"
CALL _load_config.cmd
if errorlevel 1 exit /b 1

echo Starting JOINER (Role=1)...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%GAME%' -ArgumentList 'Intro_Persistent?game=Multiplayer.OLTogetherGame?Role=1?QuickPlay','-log','-WINDOWED','-ResX=1920','-ResY=1080','-WinX=50','-WinY=200','-nosteam'"

echo.
echo Done! Wait for the game to load and connect.
pause
exit /b 0