@echo off
rem 以管理员身份运行 migrate-legacy-install.ps1（右键本文件 -> 以管理员身份运行）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0migrate-legacy-install.ps1"
pause
