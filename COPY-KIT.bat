@echo off
rem Survival Station - copy this kit to another USB drive or computer. No internet needed.
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Minimized -File "%~dp0setup\copy-kit.ps1"
if errorlevel 1 pause
