@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"
CALL _load_config.cmd

:MENU
cls
echo.
echo   Outlast Multiplayer Mod
echo   --------------------------------
echo   [1] Run Host
echo   [2] Run Joiner
echo   [3] Compile
echo   [4] Run Server  (requires Python)
echo   [5] Settings
echo.
echo   [0] Exit
echo.
set /p CHOICE=    Choice:

if "%CHOICE%"=="1" goto HOST
if "%CHOICE%"=="2" goto JOINER
if "%CHOICE%"=="3" goto COMPILE
if "%CHOICE%"=="4" goto SERVER
if "%CHOICE%"=="5" goto SETTINGS
if "%CHOICE%"=="0" exit /b 0
goto MENU

:: ─────────────────────────────────────────────
:HOST
cls
if "%GAME_DIR%"=="" ( echo   [ERROR] Game path not set. Go to [5] Settings. & pause & goto MENU )
call :WRITE_MULTIPLAYER_INI
echo   Starting HOST (Role=0)...
start "" "%GAME%" "Intro_Persistent?game=Multiplayer.OLTogetherGame?Role=0" -log -nosteam
echo   Done!
pause
goto MENU

:: ─────────────────────────────────────────────
:JOINER
cls
if "%GAME_DIR%"=="" ( echo   [ERROR] Game path not set. Go to [5] Settings. & pause & goto MENU )
echo   Check your settings in [5] Settings before joining.
echo   --------------------------------
:JOINER_INPUT
set ROLE=
set /p ROLE=    Enter your role number (1-255):
if "%ROLE%"=="" goto JOINER_INPUT
set /a ROLE_NUM=%ROLE%
if %ROLE_NUM% LSS 1 ( echo   Invalid number. & goto JOINER_INPUT )
if %ROLE_NUM% GTR 255 ( echo   Invalid number. & goto JOINER_INPUT )
call :WRITE_MULTIPLAYER_INI
echo.
echo   Starting JOINER (Role=%ROLE_NUM%)...
start "" "%GAME%" "Intro_Persistent?game=Multiplayer.OLTogetherGame?Role=%ROLE_NUM%" -log -nosteam
echo   Done! Wait for the game to load and connect.
pause
goto MENU

:: ─────────────────────────────────────────────
:COMPILE
cls
if "%UDK%"=="" ( echo   [ERROR] UDK path not set in config.ini. & pause & goto MENU )
echo   [1/2] Compiling UnrealScript...
"%UDK%" make
if errorlevel 1 ( echo. & echo   Compile failed. & pause & goto MENU )
echo   [2/2] Copying Multiplayer.u to game directory...
mkdir "%DST_DIR%" 2>nul
copy /Y "%SRC%" "%DST%" >nul
if not exist "%DST%" ( echo. & echo   Copy failed: %DST% & pause & goto MENU )
echo.
echo   Done! Copied to: %DST%
pause
goto MENU

:: ─────────────────────────────────────────────
:SERVER
cls
set PY=python
where python >nul 2>&1
if errorlevel 1 (
    where py >nul 2>&1
    if errorlevel 1 ( echo   [ERROR] Python not found. & pause & goto MENU )
    set PY=py
)
echo   [1/2] Killing old processes...
taskkill /F /IM OLGame.exe >nul 2>&1
taskkill /F /IM python.exe >nul 2>&1
taskkill /F /IM py.exe     >nul 2>&1
timeout /t 1 /nobreak >nul
echo   [2/2] Starting TCP relay server...
start "" "%PY%" "%~dp0%BRIDGE_SCRIPT%"
timeout /t 2 /nobreak >nul
echo.
echo   Server launched. Close the server window to shut down.
pause
goto MENU

:: ─────────────────────────────────────────────
:SETTINGS
cls
set "_D=%GAME_DIR%"
if "%GAME_DIR%"=="" set "_D=(not set)"
set "_N=%NICKNAME%"
if "%NICKNAME%"=="" set "_N=(empty)"
echo.
echo   Settings
echo   --------------------------------
echo   [1] Game Path:        %_D%
echo   [2] Server IP:        %SERVER_HOST%
echo   [3] Server Port:      %SERVER_PORT%
echo   [4] Nickname:         %_N%
echo   [5] Fade Nearby:      %FADE_NEARBY%
echo   [6] Game Version:     %GAME_VERSION%
echo.
echo   [0] Back
echo.
set /p SCHOICE=    Choice:
if "%SCHOICE%"=="1" goto EDIT_GAMEDIR
if "%SCHOICE%"=="2" goto EDIT_IP
if "%SCHOICE%"=="3" goto EDIT_PORT
if "%SCHOICE%"=="4" goto EDIT_NICK
if "%SCHOICE%"=="5" goto EDIT_FADE
if "%SCHOICE%"=="6" goto EDIT_VERSION
if "%SCHOICE%"=="0" goto MENU
goto SETTINGS

:EDIT_GAMEDIR
set NEW_VAL=
set /p NEW_VAL=    Game path (Enter to keep current):
if "%NEW_VAL%"=="" goto SETTINGS
set "GAME_DIR=%NEW_VAL%"
set "GAME=%NEW_VAL%\Binaries\Win64\OLGame.exe"
set "DST_DIR=%NEW_VAL%\OLGame\CookedPCConsole\MultiplayerContent"
set "DST=%DST_DIR%\Multiplayer.u"
set "SAVE_KEY=GAME_DIR" & set "SAVE_VAL=%NEW_VAL%" & call :SAVE_CONFIG
goto SETTINGS

:EDIT_IP
set NEW_VAL=
set /p NEW_VAL=    Server IP (Enter to keep current):
if "%NEW_VAL%"=="" goto SETTINGS
set "SERVER_HOST=%NEW_VAL%"
set "SAVE_KEY=SERVER_HOST" & set "SAVE_VAL=%NEW_VAL%" & call :SAVE_CONFIG
goto SETTINGS

:EDIT_PORT
set NEW_VAL=
set /p NEW_VAL=    Server Port (Enter to keep current):
if "%NEW_VAL%"=="" goto SETTINGS
set /a PORT_NUM=%NEW_VAL%
if %PORT_NUM% LSS 1 ( echo   Invalid port. & pause & goto SETTINGS )
if %PORT_NUM% GTR 65535 ( echo   Invalid port. & pause & goto SETTINGS )
set "SERVER_PORT=%NEW_VAL%"
set "SAVE_KEY=SERVER_PORT" & set "SAVE_VAL=%NEW_VAL%" & call :SAVE_CONFIG
goto SETTINGS

:EDIT_NICK
set NEW_VAL=
set /p NEW_VAL=    Nickname (Enter to keep current):
if "%NEW_VAL%"=="" goto SETTINGS
set "NICKNAME=%NEW_VAL%"
set "SAVE_KEY=NICKNAME" & set "SAVE_VAL=%NEW_VAL%" & call :SAVE_CONFIG
goto SETTINGS

:EDIT_FADE
set NEW_VAL=
set /p NEW_VAL=    Fade nearby - true/false (Enter to keep current):
if "%NEW_VAL%"=="" goto SETTINGS
if /i "%NEW_VAL%"=="true"  ( set "FADE_NEARBY=true"  & goto SAVE_FADE )
if /i "%NEW_VAL%"=="false" ( set "FADE_NEARBY=false" & goto SAVE_FADE )
echo   Enter true or false.
pause
goto SETTINGS
:SAVE_FADE
set "SAVE_KEY=FADE_NEARBY" & set "SAVE_VAL=%FADE_NEARBY%" & call :SAVE_CONFIG
goto SETTINGS

:EDIT_VERSION
cls
echo.
echo   Game Version
echo   --------------------------------
echo   [1] Win64  (default, most users)
echo   [2] Win32
echo.
echo   [0] Back
echo.
set /p VCHOICE=    Choice:
if "%VCHOICE%"=="1" ( set "GAME_VERSION=Win64" & goto SAVE_VERSION )
if "%VCHOICE%"=="2" ( set "GAME_VERSION=Win32" & goto SAVE_VERSION )
if "%VCHOICE%"=="0" goto SETTINGS
goto EDIT_VERSION
:SAVE_VERSION
set "GAME=%GAME_DIR%\Binaries\%GAME_VERSION%\OLGame.exe"
set "SAVE_KEY=GAME_VERSION" & set "SAVE_VAL=%GAME_VERSION%" & call :SAVE_CONFIG
goto SETTINGS

:: ─────────────────────────────────────────────
:WRITE_MULTIPLAYER_INI
mkdir "%GAME_DIR%\OLGame\Config" 2>nul
(
echo [Multiplayer.OLTogetherLink]
echo ServerHost=%SERVER_HOST%
echo ServerPort=%SERVER_PORT%
echo PlayerNickname=%NICKNAME%
echo bFadeNearbyPlayers=%FADE_NEARBY%
echo NearbyFadeDistance=200.0
echo NearbyFadeHysteresis=50.0
) > "%GAME_DIR%\OLGame\Config\DefaultMultiplayer.ini"
exit /b

:SAVE_CONFIG
powershell -ExecutionPolicy Bypass -File "%~dp0Scripts\save_config.ps1"
exit /b
