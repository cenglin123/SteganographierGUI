@echo off
rem Elevation companion for the right-click menu installer.
rem
rem The v1.3.9 distribution shipped InstallElevated.cmd so the menu could be
rem registered without opening an elevated shell by hand; this restores that for
rem the current entry point. The Inno installer already runs elevated and calls
rem Install-ContextMenu.ps1 directly, so this file is only for manual re-runs.
rem
rem This file is deliberately pure ASCII: batch files are read using the console
rem code page, so non-ASCII content (and especially a UTF-8 BOM) behaves
rem differently per machine. The installer is found by pattern instead of by
rem naming it, which is what the v1.3.9 script did too.
setlocal

set "SCRIPT_DIR=%~dp0"
set "INSTALL_CMD="
for %%f in ("%SCRIPT_DIR%01-*.cmd") do set "INSTALL_CMD=%%~ff"

if not defined INSTALL_CMD goto :notfound
if not exist "%INSTALL_CMD%" goto :notfound

rem Already elevated? Then just run it in this window.
net session >nul 2>&1
if %errorlevel% equ 0 (
    call "%INSTALL_CMD%"
    exit /b %errorlevel%
)

echo Requesting administrator rights...
set "ELEVATE_TARGET=%INSTALL_CMD%"
rem The path is handed to Start-Process as its own argument, so spaces and
rem apostrophes need no escaping at all.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = $env:ELEVATE_TARGET; $r = Start-Process -FilePath $p -Verb RunAs -Wait -PassThru; if ($r -and $r.HasExited) { exit $r.ExitCode } else { exit 0 }"
set "ELEVATE_EXIT=%errorlevel%"

if not "%ELEVATE_EXIT%"=="0" (
    echo [ERROR] Elevation failed, was cancelled, or the installer reported a failure ^(exit %ELEVATE_EXIT%^).
    pause
    exit /b %ELEVATE_EXIT%
)
exit /b 0

:notfound
echo [ERROR] Could not find "01-*.cmd" next to this script in "%SCRIPT_DIR%".
pause
exit /b 1
