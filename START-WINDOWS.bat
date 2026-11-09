@echo off
setlocal EnableDelayedExpansion
rem use Windows' own tools even if Git/Cygwin put look-alikes (curl, ping) first on PATH
set "SYS=%SystemRoot%\System32"
title Survival Station
cd /d "%~dp0"

set PORT=8080
set LIBPORT=8090
set MAPPORT=8092

rem (messages are English / Portugues, without accents so any console code page shows them)
rem version from portal\version.js, the one place it is set
set "VER="
for /f "tokens=2 delims='" %%v in ('findstr /c:"SURVIVAL_VERSION" "portal\version.js" 2^>nul') do if not defined VER set "VER=%%v"
echo.
echo  ==============================================
echo    SURVIVAL STATION %VER%  -  offline AI + library
echo                         IA offline + biblioteca
echo  ==============================================
echo  Use at your own risk: free resources gathered from others, not a substitute
echo  for emergency services. The AI can be wrong. No responsibility accepted.
echo  Use por sua conta e risco: recursos gratuitos de terceiros, nao substitui o
echo  socorro. A IA pode errar. Os autores nao se responsabilizam.
echo.

rem ---- close a Survival Station that is still running (an earlier start never shut down, or another copy)
if exist "setup\stop-old-kit.ps1" "%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\stop-old-kit.ps1"
rem ---- if this window is closed with its X (not a key press), close the servers too: none keep running on their own
if exist "setup\watch-kit.ps1" start "" /min "%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup\watch-kit.ps1"

rem ---- library server (all .zim files in library\)
rem kiwix-serve names each book after the path it was given, so run it inside library\ with bare
rem file names - "library\x.zim" would produce broken article links. It answers under /library, so the
rem secure address (Caddy, see below) can pass /library on to it.
set ZIMS=
for %%z in (library\*.zim) do set ZIMS=!ZIMS! "%%~nxz"
if defined ZIMS (
  if exist "kiwix\win\kiwix-serve.exe" start "Library server" /min /d "%~dp0library" "%~dp0kiwix\win\kiwix-serve.exe" --port %LIBPORT% --urlRootLocation /library !ZIMS!
) else echo  No library files in library\  /  Nenhum arquivo na biblioteca.

rem ---- voice: speech to text for the chat (whisper.cpp). It listens on this computer only: phones reach it
rem      through the secure address (browsers allow the microphone only on https or on localhost)
set "WMODEL="
for %%w in (models\whisper\*.bin) do set "WMODEL=%%w"
if defined WMODEL if exist "tools\win\whisper\whisper-server.exe" start "Voice server" /min "%~dp0tools\win\whisper\whisper-server.exe" -m "%~dp0!WMODEL!" --host 127.0.0.1 --port 8093

rem ---- map server for maps over 2 GB (the AI server can't send files that big on Windows)
if exist "tools\win\pmtiles.exe" start "Map server" /min /d "%~dp0portal\maps" "%~dp0tools\win\pmtiles.exe" serve . --port=%MAPPORT% --cors=* --quiet

if not exist "engine\win\llama-server.exe" goto noai

rem ---- pick an AI model (Qwen3-4B by default, picked automatically after 10 seconds)
set n=0
set def=1
for %%f in (models\*.gguf) do (
  set /a n+=1
  set "model!n!=%%f"
  rem a model with a vision part in models\mmproj\ can look at photos
  if exist "models\mmproj\%%~nxf" (echo    !n!. %%~nf   [photos / fotos]) else echo    !n!. %%~nf
  echo %%~nf | findstr /i "Qwen3-4B" >nul && set def=!n!
)
if %n%==0 goto noai
rem on battery, the smallest model is the default: it uses far less power
set "ONBATTERY="
for /f %%b in ('%SYS%\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Where-Object BatteryStatus -eq 1) { Write-Output yes }"') do set "ONBATTERY=%%b"
if defined ONBATTERY (
  set n2=0
  for %%f in (models\*.gguf) do (
    set /a n2+=1
    echo %%~nf | findstr /i "Llama-3.2-1B" >nul && set def=!n2!
  )
)
set keys=123456789
set keys=!keys:~0,%n%!0
echo.
echo    0. No AI - library, maps, cards and tools only (fast, low memory)
echo       Sem IA - so biblioteca, mapas, cartoes e ferramentas (rapido, pouca memoria)
if defined ONBATTERY echo  On battery: the smallest model is picked to save power.  /  Na bateria: o menor modelo foi escolhido para economizar.
echo  Old or slow computer? Pick Llama-3.2-1B, or 0 for No AI.  /  Computador antigo ou lento? Escolha Llama-3.2-1B, ou 0 para Sem IA.
"%SYS%\choice.exe" /c !keys! /t 10 /d !def! /n /m "  Choice / Escolha [1-%n%, 0=No AI] (default/padrao !def!): "
set pick=!errorlevel!
if !pick! GTR %n% goto startnoai
set "MODEL=!model%pick%!"
echo.
echo  Starting AI / Iniciando a IA: !MODEL!

rem ---- AI server (also serves the portal web pages); with its vision part when the model has one
set "MMFILE="
for %%m in ("!MODEL!") do if exist "models\mmproj\%%~nxm" set "MMFILE=models\mmproj\%%~nxm"
if defined MMFILE (
  start "AI server" /min "engine\win\llama-server.exe" -m "!MODEL!" --mmproj "!MMFILE!" --host 0.0.0.0 --port %PORT% --path portal -c 8192
) else (
  start "AI server" /min "engine\win\llama-server.exe" -m "!MODEL!" --host 0.0.0.0 --port %PORT% --path portal -c 8192
)

echo  Loading, can take a minute...  /  Carregando, pode levar um minuto...
for /l %%i in (1,1,180) do (
  "%SYS%\curl.exe" -s -o nul -f http://127.0.0.1:%PORT%/health && goto ready
  "%SYS%\ping.exe" -n 2 127.0.0.1 >nul
)
echo  AI did not start. Try a smaller model, or check the "AI server" window.
echo  A IA nao iniciou. Tente um modelo menor, ou veja a janela "AI server".
goto end

:ready
rem ---- this computer's network addresses (for the home page's QR code) and, with the Voice extra, the
rem      secure address https://...:8443 (Caddy), so phones may use the microphone
set HTTPSPORT=8443
"%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\network.ps1" -Kit "%~dp0." -Port %PORT% -LibPort %LIBPORT% -MapPort %MAPPORT% -HttpsPort %HTTPSPORT% >nul 2>&1
if exist "tools\win\caddy\caddy.exe" if exist "%TEMP%\survival-Caddyfile" start "Secure server" /min "%~dp0tools\win\caddy\caddy.exe" run --config "%TEMP%\survival-Caddyfile" --adapter caddyfile
rem ---- kit helper for the portal's "My kit" page (this computer only; stops when the AI stops)
if exist "setup\kit-control.ps1" start "" /min "%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup\kit-control.ps1" -Root "%~dp0."
rem ---- shared map pins for everyone on this Wi-Fi or hotspot (stops when the AI stops)
if exist "setup\share-server.ps1" start "" /min "%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup\share-server.ps1" -Root "%~dp0."
start "" http://localhost:%PORT%/
echo.
echo  READY / PRONTO:  http://localhost:%PORT%/
echo.
echo  Phones on the same Wi-Fi or hotspot  /  Celulares no mesmo Wi-Fi ou roteador:
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  set ip=%%a
  echo     http://!ip: =!:%PORT%/
)
if exist "tools\win\caddy\caddy.exe" (
  echo.
  echo  Microphone on phones: the same address with https and port %HTTPSPORT%, e.g.
  echo  Microfone no celular: o mesmo endereco com https e porta %HTTPSPORT%, por exemplo
  for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
    set ip=%%a
    echo     https://!ip: =!:%HTTPSPORT%/
  )
  echo  The phone warns once that it is "not private": choose Advanced / Show details, then continue.
  echo  O celular avisa uma vez que "nao e particular": escolha Avancado / Mostrar detalhes e continue.
)
echo  Firewall question? Click Allow.  /  Pergunta do firewall? Clique em Permitir.
goto end

:startnoai
echo.
echo  Starting without AI (library, maps, cards, tools).  /  Iniciando sem IA (biblioteca, mapas, cartoes, ferramentas).
if not exist "setup\portal-server.ps1" goto noai_files
start "Portal server" /min "%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\portal-server.ps1" -Root "%~dp0." -Port %PORT%
echo  Loading...  /  Carregando...
for /l %%i in (1,1,30) do (
  "%SYS%\curl.exe" -s -o nul -f http://127.0.0.1:%PORT%/ && goto noai_ready
  "%SYS%\ping.exe" -n 2 127.0.0.1 >nul
)
goto noai_files

:noai_ready
start "" http://localhost:%PORT%/
echo.
echo  READY - no AI / PRONTO - sem IA:  http://localhost:%PORT%/
if defined ZIMS echo  Library / Biblioteca: on / ligada
echo  The AI and photo/voice features are off. To use them, or phones, restart and pick a model.
echo  A IA e os recursos de foto/voz ficam desligados. Para usar, ou para celulares, reinicie e escolha um modelo.
echo  Firewall question? Click Allow.  /  Pergunta do firewall? Clique em Permitir.
goto end

:noai
echo  No AI model installed - starting without AI.  /  Sem modelo de IA - iniciando sem IA.
echo  (Add one later with MAKE-USB.bat and internet.  /  Adicione depois com o MAKE-USB.bat e internet.)
goto startnoai

:noai_files
echo  Opening the offline pages as files (the map and search need the server).
echo  Abrindo as paginas como arquivos (o mapa e a busca precisam do servidor).
if defined ZIMS echo  Library / Biblioteca: http://localhost:%LIBPORT%/library/
start "" "%~dp0portal\index.html"

:end
echo.
echo  Leave this window open. Press any key to SHUT DOWN.
echo  Deixe esta janela aberta. Aperte qualquer tecla para DESLIGAR.
echo  Or use the red "Shut down the kit" button on the home page. Closing the browser does NOT stop the kit.
echo  Ou use o botao vermelho "Desligar o kit" na pagina inicial. Fechar o navegador NAO desliga o kit.
pause >nul
taskkill /f /im llama-server.exe >nul 2>&1
taskkill /f /im kiwix-serve.exe >nul 2>&1
taskkill /f /im pmtiles.exe >nul 2>&1
taskkill /f /im whisper-server.exe >nul 2>&1
taskkill /f /im caddy.exe >nul 2>&1
rem the "No AI" web server is a PowerShell process; close it by its command line
"%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'portal-server\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
endlocal
