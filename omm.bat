@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"
CALL _load_config.cmd
if errorlevel 1 exit /b 1

:MENU
cls
echo.
echo   Outlast Multiplayer Mod
echo   --------------------------------
echo   [1] Run Host
echo   [2] Run Joiner
echo   [3] Compile
echo   [4] Run Server  (requires Python)
echo.
echo   [0] Exit
echo.
set /p CHOICE=    Choice:

if "%CHOICE%"=="1" goto HOST
if "%CHOICE%"=="2" goto JOINER
if "%CHOICE%"=="3" goto COMPILE
if "%CHOICE%"=="4" goto SERVER
if "%CHOICE%"=="0" exit /b 0
goto MENU

:: ─────────────────────────────────────────────
:HOST
cls
echo   Starting HOST (Role=0)...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%GAME%' -ArgumentList 'Intro_Persistent?game=Multiplayer.OLTogetherGame?Role=0?QuickPlay','-log','-WINDOWED','-ResX=1920','-ResY=1080','-WinX=50','-WinY=200','-nosteam'"
echo   Done!
pause
goto MENU

:: ─────────────────────────────────────────────
:JOINER
cls
echo   Check that DefaultMultiplayer.ini settings are correct.
echo   --------------------------------
:JOINER_INPUT
set ROLE=
set /p ROLE=    Enter your role number (1-255):
if "%ROLE%"=="" goto JOINER_INPUT
set /a ROLE_NUM=%ROLE%
if %ROLE_NUM% LSS 1 (
    echo   Invalid number. Enter a value between 1 and 255.
    goto JOINER_INPUT
)
if %ROLE_NUM% GTR 255 (
    echo   Invalid number. Enter a value between 1 and 255.
    goto JOINER_INPUT
)
echo.
echo   Starting JOINER (Role=%ROLE_NUM%)...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%GAME%' -ArgumentList 'Intro_Persistent?game=Multiplayer.OLTogetherGame?Role=%ROLE_NUM%?QuickPlay','-log','-WINDOWED','-ResX=1920','-ResY=1080','-WinX=50','-WinY=200','-nosteam'"
echo   Done! Wait for the game to load and connect.
pause
goto MENU

:: ─────────────────────────────────────────────
:COMPILE
cls
echo   [1/2] Compiling UnrealScript...
"%UDK%" make
if errorlevel 1 (
    echo.
    echo   Compile failed.
    pause
    goto MENU
)
echo   [2/2] Copying Multiplayer.u to game directory...
mkdir "%DST_DIR%" 2>nul
copy /Y "%SRC%" "%DST%" >nul
if not exist "%DST%" (
    echo.
    echo   Copy failed. Destination: %DST%
    pause
    goto MENU
)
echo.
echo   Done! File copied to: %DST%
pause
goto MENU

:: ─────────────────────────────────────────────
:SERVER
cls
set PY=python
where python >nul 2>&1
if errorlevel 1 (
    where py >nul 2>&1
    if errorlevel 1 (
        echo   [ERROR] Python not found. Install Python or add it to PATH.
        pause
        goto MENU
    )
    set PY=py
)
echo   [1/2] Killing old processes...
taskkill /F /IM OLGame.exe >nul 2>&1
taskkill /F /IM python.exe >nul 2>&1
taskkill /F /IM py.exe     >nul 2>&1
timeout /t 1 /nobreak >nul
echo   [2/2] Starting TCP relay server...
powershell -Command "Start-Process -WindowStyle Normal -FilePath '%PY%' -ArgumentList '%~dp0%BRIDGE_SCRIPT%'"
timeout /t 2 /nobreak >nul
echo.
echo   Server launched. Close the server window to shut down.
pause
goto MENU
