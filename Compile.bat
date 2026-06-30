@echo off
setlocal enabledelayedexpansion
echo ------------------------------------------
echo OLTogether - Compile + Copy
echo ------------------------------------------

cd /d "%~dp0"
CALL _load_config.cmd
if errorlevel 1 exit /b 1

echo [1/2] Compiling UnrealScript...
"%UDK%" make
if errorlevel 1 (
    echo.
    echo Compile failed.
    pause
    exit /b 1
)

echo [2/2] Copying Multiplayer.u to game directory...
mkdir "%DST_DIR%" 2>nul
copy /Y "%SRC%" "%DST%" >nul
if not exist "%DST%" (
    echo.
    echo Copy failed. Destination: %DST%
    pause
    exit /b 1
)

echo.
echo Done! File copied to: %DST%
pause
exit /b 0