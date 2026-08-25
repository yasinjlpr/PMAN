@echo off
setlocal EnableExtensions

title PMAN Uninstaller

set "INSTALL_DIR=%LOCALAPPDATA%\PMAN"

echo.
echo ======================================================
echo                 PMAN UNINSTALLER
echo ======================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$dir = [Environment]::ExpandEnvironmentVariables('%%LOCALAPPDATA%%\PMAN');" ^
  "$path = [Environment]::GetEnvironmentVariable('Path', 'User');" ^
  "if ($path) {" ^
  "  $parts = $path -split ';' | Where-Object { $_ -and $_.Trim() -ne '' -and $_ -ne $dir };" ^
  "  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User');" ^
  "}"

if exist "%INSTALL_DIR%" (
  rmdir /s /q "%INSTALL_DIR%"
  echo Directory removed.
) else (
  echo Directory not found: %INSTALL_DIR%
)

echo.
echo PMAN has been removed from this computer.
echo.
echo Close and reopen CMD or PowerShell for the PATH change to take effect.
echo.
pause
exit /b 0