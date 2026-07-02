@echo off
REM Reads config.ini and exports variables. Must be called via CALL.
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0config.ini") do (
    set "%%A=%%B"
)
if "%GAME_DIR%"=="" exit /b 0
set "GAME=%GAME_DIR%\Binaries\Win64\OLGame.exe"
set "DST_DIR=%GAME_DIR%\OLGame\CookedPCConsole\MultiplayerContent"
set "DST=%DST_DIR%\Multiplayer.u"
