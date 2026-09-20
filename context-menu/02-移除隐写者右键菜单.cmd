@echo off
setlocal DisableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "INSTALL_ROOT=%SCRIPT_DIR:~0,-1%"
rem Uninstall-ContextMenu.ps1 sits next to this file in the repository, and under
rem context-menu\ in an installed tree, where only the entry points are kept at the
rem root. Probe for it rather than hard-coding, so this one file works in either
rem layout. This file must stay pure ASCII: cmd.exe reads it through the console
rem code page, and a UTF-8 BOM would break its first line.
set "UNINSTALLER=%SCRIPT_DIR%Uninstall-ContextMenu.ps1"
if not exist "%UNINSTALLER%" set "UNINSTALLER=%SCRIPT_DIR%context-menu\Uninstall-ContextMenu.ps1"
if not exist "%UNINSTALLER%" (
    echo [ERROR] Uninstall-ContextMenu.ps1 not found next to this script or in context-menu\
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UNINSTALLER%" -InstallRoot "%INSTALL_ROOT%" %*
exit /b %errorlevel%
