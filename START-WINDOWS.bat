@echo off
setlocal EnableDelayedExpansion
rem use Windows' own tools even if Git/Cygwin put look-alikes (curl, ping) first on PATH
set "SYS=%SystemRoot%\System32"
title Survival Station
cd /d "%~dp0"

set PORT=8080
set LIBPORT=8090

rem (messages are English / Portugues, without accents so any console code page shows them)
rem version from portal\version.js, the one place it is set
set "VER="
for /f "tokens=2 delims='" %%v in ('findstr /c:"SURVIVAL_VERSION" "portal\version.js" 2^>nul') do if not defined VER set "VER=%%v"
echo.
echo  ==============================================
echo    SURVIVAL STATION %VER%  -  offline AI + library
echo                         IA offline + biblioteca
echo  ==============================================
echo.

rem ---- library server (all .zim files in library\)
rem kiwix-serve names each book after the path it was given, so run it inside library\ with bare
rem file names - "library\x.zim" would produce broken article links
set ZIMS=
for %%z in (library\*.zim) do set ZIMS=!ZIMS! "%%~nxz"
if defined ZIMS (
  if exist "kiwix\win\kiwix-serve.exe" start "Library server" /min /d "%~dp0library" "%~dp0kiwix\win\kiwix-serve.exe" --port %LIBPORT% !ZIMS!
) else echo  No library files in library\  /  Nenhum arquivo na biblioteca.

if not exist "engine\win\llama-server.exe" goto noai

rem ---- pick an AI model (Qwen3-4B by default, picked automatically after 10 seconds)
set n=0
set def=1
for %%f in (models\*.gguf) do (
  set /a n+=1
  set "model!n!=%%f"
  echo    !n!. %%~nf
  echo %%~nf | findstr /i "Qwen3-4B" >nul && set def=!n!
)
if %n%==0 goto noai
set keys=123456789
set keys=!keys:~0,%n%!
if %n% GTR 1 (
  echo.
  echo  Old or slow computer? Pick Llama-3.2-1B.  /  Computador antigo ou lento? Escolha Llama-3.2-1B.
  "%SYS%\choice.exe" /c !keys! /t 10 /d !def! /n /m "  AI model / Modelo de IA [1-%n%] (default/padrao !def!): "
  set pick=!errorlevel!
) else set pick=1
set "MODEL=!model%pick%!"
echo.
echo  Starting AI / Iniciando a IA: !MODEL!

rem ---- AI server (also serves the portal web pages)
start "AI server" /min "engine\win\llama-server.exe" -m "!MODEL!" --host 0.0.0.0 --port %PORT% --path portal -c 8192

echo  Loading, can take a minute...  /  Carregando, pode levar um minuto...
for /l %%i in (1,1,180) do (
  "%SYS%\curl.exe" -s -o nul -f http://127.0.0.1:%PORT%/health && goto ready
  "%SYS%\ping.exe" -n 2 127.0.0.1 >nul
)
echo  AI did not start. Try a smaller model, or check the "AI server" window.
echo  A IA nao iniciou. Tente um modelo menor, ou veja a janela "AI server".
goto end

:ready
rem ---- kit helper for the portal's "My kit" page (this computer only; stops when the AI stops)
if exist "setup\kit-control.ps1" start "" /min "%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup\kit-control.ps1" -Root "%~dp0."
start "" http://localhost:%PORT%/
echo.
echo  READY / PRONTO:  http://localhost:%PORT%/
echo.
echo  Phones on the same Wi-Fi or hotspot  /  Celulares no mesmo Wi-Fi ou roteador:
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  set ip=%%a
  echo     http://!ip: =!:%PORT%/
)
echo  Firewall question? Click Allow.  /  Pergunta do firewall? Clique em Permitir.
goto end

:noai
echo  No AI found - opening the offline pages only.  /  IA nao encontrada - abrindo so as paginas.
echo  (Run setup\build-drive.ps1 with internet  /  Rode setup\build-drive.ps1 com internet)
if defined ZIMS echo  Library / Biblioteca: http://localhost:%LIBPORT%/
start "" "%~dp0portal\index.html"

:end
echo.
echo  Leave this window open. Press any key to SHUT DOWN.
echo  Deixe esta janela aberta. Aperte qualquer tecla para DESLIGAR.
pause >nul
taskkill /f /im llama-server.exe >nul 2>&1
taskkill /f /im kiwix-serve.exe >nul 2>&1
endlocal
