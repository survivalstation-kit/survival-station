@echo off
rem Survival Station - step-by-step USB drive builder for Windows.
rem Lists the drives, asks a few questions, then runs setup\build-drive.ps1 for you.
setlocal EnableDelayedExpansion
title Survival Station - USB builder
cd /d "%~dp0"
set "SYS=%SystemRoot%\System32"
set "PS=%SYS%\WindowsPowerShell\v1.0\powershell.exe"
set "PRESETS=brazil portugal usa alaska hawaii canada canada-south rio-grande-do-sul santa-catarina parana sao-paulo rio-de-janeiro minas-gerais bahia pernambuco"

if not exist "setup\build-drive.ps1" (
  echo.
  echo   setup\build-drive.ps1 not found. Run this file from the Survival Station folder.
  echo   setup\build-drive.ps1 nao encontrado. Rode este arquivo na pasta do Survival Station.
  pause
  exit /b 1
)

rem the builder window (checkboxes + space needed); "MAKE-USB.bat text" asks step-by-step questions instead
if /i not "%~1"=="text" (
  echo.
  echo   Opening the builder window... / Abrindo a janela do construtor...
  echo.
  echo   If you don't see it, click "Survival Station" in the taskbar.
  echo   Se nao aparecer, clique em "Survival Station" na barra de tarefas.
  echo   This black window closes by itself when you close the builder.
  echo   Esta janela preta fecha sozinha quando voce fechar o construtor.
  %PS% -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Minimized -File "%~dp0setup\builder-gui.ps1"
  if not errorlevel 1 exit /b 0
  echo   The window could not open, using questions instead. / A janela nao abriu, usando perguntas.
  pause
)

:menu
set "VER="
for /f "tokens=2 delims='" %%v in ('findstr /c:"SURVIVAL_VERSION" "portal\version.js" 2^>nul') do if not defined VER set "VER=%%v"
cls
echo.
echo   ==============================================================
echo    SURVIVAL STATION %VER% - build the USB drive / montar o pendrive
echo   ==============================================================
echo.
echo    1  Build a drive or add to it     / Montar um pendrive ou adicionar itens
echo    2  Refresh documents + maps list  / Atualizar lista de documentos e mapas
echo    3  Test a finished drive          / Testar um pendrive pronto
echo    4  Update what is on a drive      / Atualizar o que ja esta no pendrive
echo    5  Copy a kit, no internet needed / Copiar um kit, sem internet
echo    6  Verify / repair a drive        / Verificar / reparar um pendrive
echo    R  Resume a stopped build         / Continuar uma montagem parada
echo    Q  Quit                           / Sair
echo.
"%SYS%\choice.exe" /c 123456RQ /n /m "   Choose / Escolha [1,2,3,4,5,6,R,Q]: "
if errorlevel 8 exit /b 0
if errorlevel 7 (
  set "ACTION=resume"
  goto pickdrive
)
if errorlevel 6 (
  set "ACTION=verify"
  goto pickdrive
)
if errorlevel 5 (
  start "" %PS% -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup\copy-kit.ps1"
  goto menu
)
set "ACTION=build"
if errorlevel 2 set "ACTION=index"
if errorlevel 3 set "ACTION=test"
if errorlevel 4 set "ACTION=update"

rem ---------------------------------------------------------------- pick the drive
:pickdrive
echo.
echo   Drives on this computer / Unidades neste computador:
echo.
echo      DRIVE FORMAT   FREE/LIVRE        SIZE  BUS   NAME
%PS% -NoProfile -Command "$v = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -and ($_.DriveLetter + ':') -ne $env:SystemDrive -and $_.DriveType -in 'Removable','Fixed' }); if (-not $v) { '     (none - plug in the USB drive / nenhuma - conecte o pendrive)' }; foreach ($d in $v) { $bus = try { (Get-Partition -DriveLetter $d.DriveLetter -ErrorAction Stop | Get-Disk).BusType } catch { '?' }; '     {0}:    {1,-6} {2,9:N1} GB {3,8:N1} GB  {4,-5} {5}' -f $d.DriveLetter, $d.FileSystem, ($d.SizeRemaining/1GB), ($d.Size/1GB), $bus, $d.FileSystemLabel }"
echo.
echo     L:    This computer, in a folder / Este computador, numa pasta (%SystemDrive%\Survival)
echo.
set "DRV="
set /p "DRV=   Drive letter, L, R to refresh, Enter to go back / Letra, L, R atualiza, Enter volta: "
if not defined DRV goto menu
set "DRV=%DRV:~0,1%"
if /i "%DRV%"=="R" goto pickdrive
if /i "%DRV%"=="L" goto local
set "DRV=%DRV%:"
if /i "%DRV%"=="%SystemDrive%" (
  echo.
  echo   %DRV% is the system disk. Pick the USB drive. / %DRV% e o disco do sistema. Escolha o pendrive.
  pause
  goto pickdrive
)
set "FS="
set "DSIZE="
for /f "usebackq tokens=1,2" %%a in (`%PS% -NoProfile -Command "$v = Get-Volume -DriveLetter '%DRV:~0,1%' -ErrorAction SilentlyContinue; if ($v -and $v.Size) { '{0} {1:N0}' -f $(if ($v.FileSystem) { $v.FileSystem } else { 'RAW' }), ($v.Size/1GB) }"`) do (
  set "FS=%%a"
  set "DSIZE=%%b"
)
if not defined FS (
  echo.
  echo   Drive %DRV% not found. / Unidade %DRV% nao encontrada.
  pause
  goto pickdrive
)
if "%ACTION%"=="test" goto test
if "%ACTION%"=="index" goto index
if "%ACTION%"=="update" goto update
if "%ACTION%"=="verify" goto verify
if "%ACTION%"=="resume" goto resume
if /i "%FS%"=="exFAT" goto tier
goto formatcheck

rem a folder on this computer: runs the same as from the USB drive, gets a desktop shortcut
:local
set "DRV=%SystemDrive%\Survival"
set /p "DRV=   Folder / Pasta [%SystemDrive%\Survival]: "
if "%DRV:~-1%"=="\" set "DRV=%DRV:~0,-1%"
set "FS=folder"
set "DSIZE=-"
if "%ACTION%"=="test" goto test
if "%ACTION%"=="index" goto index
if "%ACTION%"=="update" goto update
if "%ACTION%"=="verify" goto verify
if "%ACTION%"=="resume" goto resume
goto tier

:formatcheck

rem ---------------------------------------------------------------- format check
echo.
echo   %DRV% is formatted as %FS%. The kit needs exFAT: FAT32 can't hold the big
echo   files (over 4 GB), and Macs and phones can't write to NTFS.
echo   %DRV% esta formatado como %FS%. O kit precisa de exFAT: FAT32 nao aceita
echo   arquivos grandes e Mac e celular nao gravam em NTFS.
echo.
echo    F  Format %DRV% as exFAT now - ERASES EVERYTHING ON %DRV% / APAGA TUDO EM %DRV%
echo    C  Continue without formatting / Continuar sem formatar
echo    B  Back / Voltar
echo.
"%SYS%\choice.exe" /c FCB /n /m "   [F,C,B]: "
if errorlevel 3 goto menu
if errorlevel 2 goto tier

"%SYS%\fltmc.exe" >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Formatting needs administrator rights. / Formatar precisa de administrador.
  "%SYS%\choice.exe" /c YN /n /m "   Restart this as administrator? / Reabrir como administrador? [Y,N]: "
  if errorlevel 2 goto menu
  %PS% -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b 0
)
echo.
set "CONFIRM=-"
set /p "CONFIRM=   To ERASE %DRV% type its letter again / Para APAGAR %DRV% digite a letra de novo: "
if /i not "%CONFIRM:~0,1%"=="%DRV:~0,1%" (
  echo   Cancelled, nothing was erased. / Cancelado, nada foi apagado.
  pause
  goto menu
)
echo   Formatting %DRV% ... / Formatando %DRV% ...
%PS% -NoProfile -Command "Format-Volume -DriveLetter '%DRV:~0,1%' -FileSystem exFAT -NewFileSystemLabel SURVIVAL -Force -Confirm:$false -ErrorAction Stop | Out-Null"
if errorlevel 1 (
  echo.
  echo   Format failed. Close any windows using %DRV% and try again.
  echo   Falhou. Feche as janelas que usam %DRV% e tente de novo.
  pause
  goto menu
)
echo   Done: %DRV% is now exFAT. / Pronto: %DRV% agora e exFAT.
set "FS=exFAT"

rem ---------------------------------------------------------------- what to put on it
:tier
echo.
echo   Destination / Destino: %DRV%   %FS%   %DSIZE% GB
echo.
echo   How much to put on it? / Quanto colocar?
echo    1  Lite      16 GB drive+  ~9 GB    2 AIs, medicine, water, food, disaster, knots, maps
echo    2  Standard  64 GB drive+  ~33 GB   + smarter AI, Wikipedia, iFixit, more books
echo    3  Full     256 GB drive+  ~139 GB  + full Wikipedia with pictures
echo.
"%SYS%\choice.exe" /c 123 /n /m "   [1,2,3]: "
set "TIER=Lite"
if errorlevel 2 set "TIER=Standard"
if errorlevel 3 set "TIER=Full"

echo.
echo   Library languages / Idiomas da biblioteca:
echo    1  English + Portugues (Brasil)   (Lite +2 GB, Standard +8 GB, Full +20 GB)
echo    2  English only / so ingles
echo    3  Portugues only / so portugues
echo.
"%SYS%\choice.exe" /c 123 /n /m "   [1,2,3]: "
set "LANGS=en,pt"
if errorlevel 2 set "LANGS=en"
if errorlevel 3 set "LANGS=pt"

echo.
echo   Street maps (the world overview is always included) / Mapas de ruas (o mapa-mundi sempre vem):
set n=0
for %%m in (%PRESETS%) do (
  set /a n+=1
  set "MAP_!n!=%%m"
  if !n! lss 10 (echo     !n!  %%m) else (echo    !n!  %%m)
)
echo   Every street: Brazil 6 GB, USA 17 GB, Canada 16 GB, southern Canada 9 GB, Alaska 0.8 GB.
echo   Pick a country OR its states, not both: Brazil includes every state, Canada includes southern Canada.
echo.
set "MAPSEL="
set /p "MAPSEL=   Numbers separated by spaces, Enter for none / Numeros separados por espaco, Enter para nenhum: "
set "MAPS="
if defined MAPSEL for %%n in (!MAPSEL!) do if defined MAP_%%n set "MAPS=!MAPS!,!MAP_%%n!"
if defined MAPS set "MAPS=!MAPS:~1!"

echo.
echo   Another area? Draw a box at bboxfinder.com and paste it (minLon,minLat,maxLon,maxLat).
echo   Outra area? Desenhe em bboxfinder.com e cole aqui. Enter to skip / para pular.
set "BBOX="
set /p "BBOX=   Box: "
set "BBOXNAME=custom"
if defined BBOX set /p "BBOXNAME=   Name for this map, no spaces / Nome do mapa, sem espacos [custom]: "

set "ZOOM=15"
set "HASMAP="
if defined MAPS set "HASMAP=1"
if defined BBOX set "HASMAP=1"
if defined HASMAP (
  echo.
  echo   Map detail / Detalhe do mapa:
  echo    1  Every street / Todas as ruas      ^(zoom 15^)
  echo    2  Half the size / Metade do tamanho ^(zoom 14^)
  echo    3  A quarter / Um quarto             ^(zoom 13^)
  "%SYS%\choice.exe" /c 123 /n /m "   [1,2,3]: "
  if errorlevel 2 set "ZOOM=14"
  if errorlevel 3 set "ZOOM=13"
)

echo.
"%SYS%\choice.exe" /c NY /n /m "   Add 70,000 English books from Gutenberg (206 GB)? / Adicionar livros (206 GB)? [N,Y]: "
set "GUT="
if errorlevel 2 set "GUT=-Gutenberg"

set "ARGS=-Drive "%DRV%" -Tier %TIER% -Languages %LANGS% -MapMaxZoom %ZOOM% %GUT%"
if defined MAPS set "ARGS=!ARGS! -Map !MAPS!"
if defined BBOX set "ARGS=!ARGS! -MapBbox "!BBOX!" -MapName !BBOXNAME!"

rem ---------------------------------------------------------------- run it
echo.
echo   Running / Executando:
echo   powershell -ExecutionPolicy Bypass -File setup\build-drive.ps1 !ARGS!
echo.
echo   It checks the sizes first and asks before downloading. If the internet drops,
echo   run this again: it picks up where it stopped.
echo   Ele confere os tamanhos e pergunta antes de baixar. Se a internet cair,
echo   rode de novo: ele continua de onde parou.
echo.
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\build-drive.ps1" !ARGS!
if errorlevel 1 (
  echo.
  echo   Something went wrong, see above. Run MAKE-USB.bat again to resume.
  echo   Algo deu errado, veja acima. Rode MAKE-USB.bat de novo para continuar.
  pause
  goto menu
)
if not exist "%DRV%\START-WINDOWS.bat" (
  pause
  goto menu
)
echo.
echo   Finished. / Pronto.
"%SYS%\choice.exe" /c YN /n /m "   Test the drive now? / Testar o pendrive agora? [Y,N]: "
if errorlevel 2 goto menu
goto test

rem ---------------------------------------------------------------- other actions
:update
echo.
echo   Newer library editions, AI engine, maps over a year old and Survival-Data.
echo   Edicoes novas da biblioteca, motor da IA, mapas com mais de um ano e Survival-Data.
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\build-drive.ps1" -Drive "%DRV%" -Update
pause
goto menu

:resume
echo.
echo   Building again what BUILD-CHOICES.txt on %DRV% lists. Finished files are skipped.
echo   Montando de novo o que o BUILD-CHOICES.txt de %DRV% lista. Arquivos prontos sao pulados.
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\build-drive.ps1" -Drive "%DRV%" -Resume
pause
goto menu

:verify
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\build-drive.ps1" -Drive "%DRV%" -Verify
pause
goto menu

:index
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\build-drive.ps1" -Drive "%DRV%" -IndexOnly
pause
goto menu

:test
if not exist "%DRV%\START-WINDOWS.bat" (
  echo.
  echo   %DRV% has no Survival Station on it yet. / %DRV% ainda nao tem o Survival Station.
  pause
  goto menu
)
start "Survival Station" /d "%DRV%\." "%DRV%\START-WINDOWS.bat"
echo.
echo   Started from %DRV% in a new window. Ask the AI something, open the library and the map.
echo   Iniciado de %DRV% em outra janela. Pergunte algo a IA, abra a biblioteca e o mapa.
pause
goto menu
