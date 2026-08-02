@echo off
setlocal
cd /d "%~dp0"
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mysql_mirth_setup.ps1"
if errorlevel 1 (
  echo.
  echo Setup returned an error. Review the log shown above.
)
pause
