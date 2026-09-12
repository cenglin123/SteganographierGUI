@echo off
rem migrate-legacy-install launcher (pure ASCII, CRLF)
rem Locate system powershell.exe absolutely: PATH lookup is unreliable on this box.
set "PS51=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS51%" set "PS51=%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS51%" (
    echo [FATAL] System PowerShell not found at %PS51%
    pause
    exit /b 1
)
"%PS51%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0migrate-legacy-install.ps1"
echo.
echo [exit code: %ERRORLEVEL%]
pause
