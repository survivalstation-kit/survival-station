<#
.SYNOPSIS
  Makes a USB drive able to start a computer (boot) into Linux Mint, so that if the computer's own disk fails
  you can still start it, use the kit, and copy your files to safety. Run by MAKE-BOOTABLE.bat (Windows).

  How: Ventoy (free, open source, https://www.ventoy.net) puts a small boot section on the drive and keeps a
  normal exFAT partition for everything else, so the kit works exactly as before. Linux Mint XFCE (an ISO file,
  ~2.9 GB, checked against the official SHA-256) goes in its ISO folder; Ventoy shows it in its boot menu.

  Installing Ventoy ERASES the drive. A drive that already has Ventoy is only given (or updated to) the newest
  Linux Mint, nothing is erased. Only USB drives are offered; never the computer's own disks.
#>
param([string]$Drive = '', [switch]$Yes)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$pt = (Get-UICulture).Name -like 'pt*'
function T($en, $p) { if ($pt) { $p } else { $en } }
function Say($en, $p, $color = 'Gray') { Write-Host (T $en $p) -ForegroundColor $color }
$Cache = Join-Path $env:LOCALAPPDATA 'SurvivalStation\boot'
New-Item -ItemType Directory -Force $Cache | Out-Null

# administrator rights: needed to write a boot section and to see the disks
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Say 'Asking for administrator rights (Windows will ask you to allow it)...' 'Pedindo permissão de administrador (o Windows vai pedir para permitir)...' Yellow
  $argList = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}"' -f $PSCommandPath
  if ($Drive) { $argList += " -Drive $Drive" }
  Start-Process (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList $argList
  exit
}

Write-Host ''
Say ' SURVIVAL STATION - make a USB drive bootable (Ventoy + Linux Mint)' ' SURVIVAL STATION - tornar um pendrive inicializável (Ventoy + Linux Mint)' Cyan
Say ' If the computer''s disk fails, start it from this drive and keep using the kit.' ' Se o disco do computador falhar, inicie por este pendrive e continue usando o kit.'
Write-Host ''

# ---------------------------------------------------------------- the USB drives
function Get-UsbDrives {
  foreach ($d in Get-Disk | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsSystem -and -not $_.IsBoot }) {
    $parts = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)
    $vols = @($parts | ForEach-Object { Get-Volume -Partition $_ -ErrorAction SilentlyContinue } | Where-Object { $_ })
    $letter = ($parts | Where-Object { $_.DriveLetter } | Sort-Object Size -Descending | Select-Object -First 1).DriveLetter
    [pscustomobject]@{
      Number = $d.Number; Name = $d.FriendlyName; Size = $d.Size; Letter = "$letter"
      Ventoy = [bool]($vols | Where-Object { $_.FileSystemLabel -eq 'VTOYEFI' })
      Kit = [bool]($letter -and (Test-Path "${letter}:\START-WINDOWS.bat"))
    }
  }
}
$usb = @(Get-UsbDrives)
if (-not $usb) { Say 'No USB drive found. Plug one in and run this again.' 'Nenhum pendrive encontrado. Conecte um e rode de novo.' Red; exit 1 }
Say ' USB drives:' ' Pendrives:'
foreach ($u in $usb) {
  $flags = @(); if ($u.Ventoy) { $flags += (T 'already bootable (Ventoy)' 'já inicializável (Ventoy)') }; if ($u.Kit) { $flags += (T 'has a Survival Station kit' 'tem um kit Survival Station') }
  Write-Host ("   {0}:  {1}  {2:N0} GB  {3}" -f $(if ($u.Letter) { $u.Letter } else { '?' }), $u.Name, ($u.Size / 1GB), ($flags -join ', '))
}
if (-not $Drive) { $Drive = Read-Host (T "`n Which drive letter?" "`n Qual a letra do pendrive?") }
$Drive = $Drive.Trim().TrimEnd(':', '\').ToUpper()
$target = $usb | Where-Object { $_.Letter -eq $Drive } | Select-Object -First 1
if (-not $target) { Say " $($Drive): is not one of the USB drives above. Nothing was changed." " $($Drive): não é um dos pendrives acima. Nada foi alterado." Red; exit 1 }

# ---------------------------------------------------------------- 1. Ventoy (erases the drive), unless it is already there
if (-not $target.Ventoy) {
  Write-Host ''
  Say (" THIS ERASES EVERYTHING ON {0}: ({1}, {2:N0} GB)." -f $Drive, $target.Name, ($target.Size / 1GB)) (" ISTO APAGA TUDO EM {0}: ({1}, {2:N0} GB)." -f $Drive, $target.Name, ($target.Size / 1GB)) Red
  if ($target.Kit) {
    Say ' It has a Survival Station kit. Copy it to this computer first with COPY-KIT.bat ("This computer"), then copy it back afterwards.' ' Ele tem um kit Survival Station. Copie para este computador antes com o COPY-KIT.bat ("Este computador") e depois copie de volta.' Yellow
  }
  $answer = if ($Yes) { 'ERASE' } else { Read-Host (T ' Type ERASE to continue (anything else stops)' ' Digite ERASE para continuar (qualquer outra coisa cancela)') }
  if ($answer -cne 'ERASE') { Say ' Stopped. Nothing was changed.' ' Cancelado. Nada foi alterado.' Green; exit 0 }

  Say "`n Getting Ventoy..." "`n Baixando o Ventoy..."
  $rel = Invoke-RestMethod 'https://api.github.com/repos/ventoy/Ventoy/releases/latest'
  $asset = $rel.assets | Where-Object { $_.name -like 'ventoy-*-windows.zip' } | Select-Object -First 1
  $zip = Join-Path $Cache $asset.name
  if (-not (Test-Path $zip) -or (Get-Item $zip).Length -ne $asset.size) { & curl.exe -L --fail -s -S -o $zip $asset.browser_download_url; if ($LASTEXITCODE) { throw 'Could not download Ventoy' } }
  # Ventoy's program is not code-signed: check the download against the checksum Ventoy publishes with the release
  $sums = (& curl.exe -L --fail -s -S (($rel.assets | Where-Object { $_.name -eq 'sha256.txt' }).browser_download_url)) -join "`n"
  $want = ([regex]::Match($sums, '([0-9a-f]{64})\s+\*?' + [regex]::Escape($asset.name))).Groups[1].Value
  if (-not $want -or (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() -ne $want) { Remove-Item $zip -Force -ErrorAction SilentlyContinue; throw 'The Ventoy download does not match its official checksum: run this again' }
  Say ' Ventoy checked against its official checksum: OK.' ' Ventoy conferido com o checksum oficial: OK.' Green
  $vdir = Join-Path $Cache ($asset.name -replace '\.zip$', '')
  if (-not (Test-Path $vdir)) { Expand-Archive $zip $vdir -Force }
  $exe = Get-ChildItem $vdir -Recurse -Filter Ventoy2Disk.exe | Select-Object -First 1
  if (-not $exe) { throw 'Ventoy2Disk.exe not found in the download' }

  Say (" Installing Ventoy {0} on disk {1} (about a minute)..." -f $rel.tag_name, $target.Number) (" Instalando o Ventoy {0} no disco {1} (cerca de um minuto)..." -f $rel.tag_name, $target.Number)
  Push-Location $exe.DirectoryName
  Remove-Item cli_done.txt, cli_percent.txt, cli_log.txt -ErrorAction SilentlyContinue
  # MBR works on old (BIOS) and new (UEFI) computers; Secure Boot support stays on (the default)
  $p = Start-Process $exe.FullName -ArgumentList "VTOYCLI /I /PhyDrive:$($target.Number)" -PassThru
  while (-not (Test-Path cli_done.txt)) {
    Start-Sleep -Milliseconds 700
    if (Test-Path cli_percent.txt) { Write-Host -NoNewline ("`r   {0}%   " -f (Get-Content cli_percent.txt -ErrorAction SilentlyContinue)) }
    if ($p.HasExited -and -not (Test-Path cli_done.txt)) { Start-Sleep 2; if (-not (Test-Path cli_done.txt)) { break } }
  }
  Write-Host ''
  $ok = (Test-Path cli_done.txt) -and ((Get-Content cli_done.txt -Raw).Trim() -eq '0')
  if (-not $ok) { Get-Content cli_log.txt -Tail 15 -ErrorAction SilentlyContinue; Pop-Location; throw 'Ventoy did not install (see the lines above)' }
  Pop-Location
  Say ' Ventoy is installed.' ' Ventoy instalado.' Green
  Start-Sleep 3
  # the big partition comes back with a drive letter; name it so it is easy to recognise
  $data = Get-Partition -DiskNumber $target.Number | Where-Object { $_.DriveLetter } | Sort-Object Size -Descending | Select-Object -First 1
  if (-not $data) { throw 'The drive has no letter after installing Ventoy: unplug it, plug it in again and run this once more (it will only add Linux)' }
  $Drive = "$($data.DriveLetter)"
  try { Set-Volume -DriveLetter $Drive -NewFileSystemLabel 'SURVIVAL' } catch { }
} else {
  Say "`n $($Drive): is already bootable: adding or updating Linux Mint only (nothing is erased)." "`n $($Drive): já é inicializável: só vou adicionar ou atualizar o Linux Mint (nada é apagado)." Green
}

# ---------------------------------------------------------------- 2. Linux Mint XFCE, checked against the official checksum
$root = "$($Drive):\"
$mirror = 'https://mirrors.edge.kernel.org/linuxmint/stable/'
$ver = (Invoke-WebRequest $mirror -UseBasicParsing).Links.href | Where-Object { $_ -match '^\d+(\.\d+)?/$' } | ForEach-Object { $_.TrimEnd('/') } |
  Sort-Object { [version]($_ + $(if ($_ -notmatch '\.') { '.0' })) } | Select-Object -Last 1
$isoName = "linuxmint-$ver-xfce-64bit.iso"
$sum = ((Invoke-WebRequest "$mirror$ver/sha256sum.txt" -UseBasicParsing).Content -split "`n" | Where-Object { $_ -match [regex]::Escape($isoName) } | Select-Object -First 1) -replace '\s.*$', ''
if ($sum -notmatch '^[0-9a-f]{64}$') { throw "No official checksum found for $isoName" }
$isoDir = Join-Path $root 'ISO'; New-Item -ItemType Directory -Force $isoDir | Out-Null
$iso = Join-Path $isoDir $isoName
$old = @(Get-ChildItem $isoDir -Filter 'linuxmint-*-xfce-64bit.iso' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $isoName })
$need = 3.2GB - $(if (Test-Path $iso) { (Get-Item $iso).Length } else { 0 })
if ((Get-PSDrive $Drive).Free -lt $need) { throw ("Not enough free space on {0}: (needs about 3 GB)" -f $Drive) }

if (-not (Test-Path $iso) -or (Get-FileHash $iso -Algorithm SHA256).Hash.ToLower() -ne $sum) {
  Say " Downloading Linux Mint $ver XFCE (~2.9 GB; it resumes if interrupted)..." " Baixando o Linux Mint $ver XFCE (~2,9 GB; continua de onde parou se cair)..."
  & curl.exe -L --fail -C - --retry 5 --retry-delay 5 -o "$iso.part" "$mirror$ver/$isoName"
  if ($LASTEXITCODE) { throw "Download failed (curl error $LASTEXITCODE): run this again to resume" }
  Say ' Checking the download against the official checksum...' ' Conferindo o download com o checksum oficial...'
  if ((Get-FileHash "$iso.part" -Algorithm SHA256).Hash.ToLower() -ne $sum) { Remove-Item "$iso.part" -Force; throw 'The download is damaged (checksum does not match): run this again' }
  Move-Item -Force "$iso.part" $iso
}
Say " Linux Mint $ver checked: OK." " Linux Mint $ver conferido: OK." Green
foreach ($o in $old) { Remove-Item $o.FullName -Force; Say " removed the older $($o.Name)" " removido o antigo $($o.Name)" }

# only look for systems in ISO\ (a big kit would make Ventoy's start menu slow to appear)
New-Item -ItemType Directory -Force (Join-Path $root 'ventoy') | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'ventoy\ventoy.json'), "{`n  `"control`": [ { `"VTOY_DEFAULT_SEARCH_ROOT`": `"/ISO`" } ]`n}`n", (New-Object Text.UTF8Encoding $false))
[IO.File]::WriteAllText((Join-Path $isoDir 'READ-ME.txt'), @"
Linux Mint, to start a computer from this drive (Survival Station).
1. Plug in the drive and turn the computer on, pressing its boot-menu key: usually F12, F11, F9, F8 or Esc
   (Apple Intel Macs: hold Option). Choose the USB drive.
2. In the Ventoy menu, choose $isoName and "Boot in normal mode".
3. First time on a computer with Secure Boot: Ventoy asks you to enroll its key once; follow the screens.
4. In Linux Mint, open the file manager, open the SURVIVAL drive and run:  bash START-LINUX.sh
Nothing is installed on the computer unless you double-click "Install Linux Mint".

Linux Mint, para iniciar um computador por este pendrive (Survival Station).
1. Conecte o pendrive e ligue o computador apertando a tecla do menu de boot: geralmente F12, F11, F9, F8 ou Esc
   (Mac Intel: segure Option). Escolha o pendrive.
2. No menu do Ventoy, escolha $isoName e "Boot in normal mode".
3. Na primeira vez num computador com Secure Boot: o Ventoy pede para registrar a chave uma vez; siga as telas.
4. No Linux Mint, abra o gerenciador de arquivos, abra o pendrive SURVIVAL e rode:  bash START-LINUX.sh
Nada é instalado no computador, a não ser que você clique duas vezes em "Install Linux Mint".
"@, (New-Object Text.UTF8Encoding $false))

Write-Host ''
Say " Done: $($Drive): can now start a computer into Linux Mint." " Pronto: $($Drive): agora consegue iniciar um computador no Linux Mint." Green
Say ' The kit''s files go on this same drive as usual (COPY-KIT.bat or MAKE-USB.bat). How to start from it: ISO\READ-ME.txt and the Help page.' ' Os arquivos do kit vão neste mesmo pendrive, como sempre (COPY-KIT.bat ou MAKE-USB.bat). Como iniciar por ele: ISO\READ-ME.txt e a página de Ajuda.'
