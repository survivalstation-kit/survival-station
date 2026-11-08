@echo off
rem Makes a USB drive able to start a computer into Linux Mint (Ventoy). See setup\make-bootable.ps1.
rem It runs from a copy in TEMP, so it keeps working even when started from the drive it erases.
title Survival Station - make a USB drive bootable
copy /y "%~dp0setup\make-bootable.ps1" "%TEMP%\survival-make-bootable.ps1" >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\survival-make-bootable.ps1"
echo.
pause
