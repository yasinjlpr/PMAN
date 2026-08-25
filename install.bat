@echo off
setlocal EnableExtensions

title PMAN Installer

set "INSTALL_DIR=%LOCALAPPDATA%\PMAN"

echo.
echo ======================================================
echo                  PMAN INSTALLER
echo ======================================================
echo.
echo Installing PMAN to:
echo %INSTALL_DIR%
echo.

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

copy /Y "%~dp0pman.bat" "%INSTALL_DIR%\pman.bat" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy pman.bat.
    pause
    exit /b 1
)

> "%INSTALL_DIR%\pman.cmd" (
    echo @echo off
    echo call "%%~dp0pman.bat" %%*
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$dir=[Environment]::ExpandEnvironmentVariables('%%LOCALAPPDATA%%\PMAN'); $path=[Environment]::GetEnvironmentVariable('Path','User'); if ([string]::IsNullOrWhiteSpace($path)) { $path='' }; $parts=$path.Split(';') | Where-Object { $_ -and $_.Trim() -ne '' -and $_.TrimEnd('\') -ne $dir.TrimEnd('\') }; $newPath=($parts + $dir) -join ';'; [Environment]::SetEnvironmentVariable('Path',$newPath,'User')"

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to add PMAN to your User PATH.
    pause
    exit /b 1
)

echo.
echo ======================================================
echo              INSTALLATION COMPLETED
echo ======================================================
echo.
echo PMAN is installed.
echo.
echo Close this terminal and open a new CMD or PowerShell.
echo Then run:
echo.
echo     pman
echo.
pause
exit /b 0
