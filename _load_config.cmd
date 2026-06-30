@echo off
REM Reads config.ini and exports variables. Must be called via CALL.
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0config.ini") do (
    set "%%A=%%B"
)
if "%GAME%"=="" (
    echo [ERROR] Failed to read config.ini. Make sure the file is in the same folder as the batch files.
    pause
    exit /b 1
)
set "DST=%DST_DIR%\Multiplayer.u"