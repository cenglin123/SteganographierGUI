@echo off
setlocal DisableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "INSTALL_ROOT=%SCRIPT_DIR:~0,-1%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Uninstall-ContextMenu.ps1" -InstallRoot "%INSTALL_ROOT%" %*
exit /b %errorlevel%
