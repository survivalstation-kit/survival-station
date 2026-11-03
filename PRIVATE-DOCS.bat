@echo off
rem Survival Station - private documents (IDs, insurance, the family plan), locked with a password.
rem They live in the private\ folder, which phones on the hotspot can't see.
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "private" mkdir "private"
:menu
echo.
echo  ==============================================
echo    PRIVATE DOCUMENTS  /  DOCUMENTOS PRIVADOS
echo  ==============================================
echo   Put files in the "private" folder, then lock them.
echo   Ponha os arquivos na pasta "private" e tranque.
echo.
echo   1. Lock the files in "private"   /  Trancar os arquivos
echo   2. Open them on this computer    /  Abrir neste computador
echo   3. Close (delete opened copies)  /  Fechar (apagar as copias abertas)
echo   4. Show the "private" folder     /  Mostrar a pasta "private"
echo   5. Quit / Sair
echo.
"%SystemRoot%\System32\choice.exe" /c 12345 /n /m "  Choose / Escolha [1-5]: "
if errorlevel 5 goto end
if errorlevel 4 (start "" explorer.exe "%~dp0private" & goto menu)
if errorlevel 3 ("%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\private-docs.ps1" -Kit "%~dp0." -Do close & goto menu)
if errorlevel 2 ("%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\private-docs.ps1" -Kit "%~dp0." -Do open & goto menu)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\private-docs.ps1" -Kit "%~dp0." -Do lock
goto menu
:end
endlocal