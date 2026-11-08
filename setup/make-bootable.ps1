<#
.SYNOPSIS
  Makes a USB drive able to start a computer (boot) into Linux Mint, so that if the computer's own disk fails
  you can still start it, use the kit, and copy your files to safety. Run by MAKE-BOOTABLE.bat (Windows).

  How: Ventoy (free, open source, https://www.ventoy.net) puts a small boot section on the drive and keeps a
  normal exFAT partition for everything else, so the kit works exactly as before. System images (ISO files,
  each checked against its official SHA-256) go in the ISO folder; Ventoy lists every one in its boot menu, so
  one drive can hold several systems and you pick which to start.

  Besides Linux Mint, you can add optional tools (all free, from their official sites):
   - SystemRescue: repair a broken Windows/Linux start-up, recover deleted files, and reset the password of a
     local Windows account you are locked out of (includes chntpw).
   - Rescuezilla: back up and restore a whole disk with simple screens.
   - Memtest86+: test the computer's memory for faults.
   - antiX: a very light Linux for old or slow computers.
   - Kali Linux: a security-testing system, for checking the security of YOUR OWN network/devices or ones you
     have written permission to test. Using it against networks or systems you do not own or have permission
     for is illegal; that is on the user, and the kit's "use at your own risk" terms apply.

  Installing Ventoy ERASES the drive. A drive that already has Ventoy keeps everything; images are only added
  or updated. Only USB drives are offered; never the computer's own disks.
#>
param([string]$Drive = '', [string]$Extras = '', [switch]$Yes)
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

# ---------------------------------------------------------------- the ISO folder, and a general "download + verify" helper
$root = "$($Drive):\"
$isoDir = Join-Path $root 'ISO'; New-Item -ItemType Directory -Force $isoDir | Out-Null
# only look for systems in ISO\ (a big kit would make Ventoy's start menu slow to appear)
New-Item -ItemType Directory -Force (Join-Path $root 'ventoy') | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'ventoy\ventoy.json'), "{`n  `"control`": [ { `"VTOY_DEFAULT_SEARCH_ROOT`": `"/ISO`" } ]`n}`n", (New-Object Text.UTF8Encoding $false))

# pull a 64-hex checksum from a .sha256 / SHA256SUMS text, matching the file name, else the first hash in it
function Find-Hash($text, $file) {
  $t = ($text -join "`n")
  $m = [regex]::Match($t, '([0-9a-f]{64})(?=\s+\*?(?:\S*/)?' + [regex]::Escape($file) + ')')
  if (-not $m.Success) { $m = [regex]::Match($t, '[0-9a-f]{64}') }
  if ($m.Success) { $m.Value.ToLower() } else { '' }
}
function Fetch-Text { foreach ($u in $args) { $r = (& curl.exe -L --fail -s $u) 2>$null; if ($LASTEXITCODE -eq 0 -and $r) { return ($r -join "`n") } }; '' }

# download an image into ISO\<File>, check it against its official SHA-256, and (for .zip images) unzip the .iso out.
# $item = @{ Name; File; Url; Sha256; Zip; Keep } ; $Keep is a wildcard of older files of the same system to clear.
function Save-Image($item) {
  $dest = Join-Path $isoDir $item.File
  if ($item.Sha256 -notmatch '^[0-9a-f]{64}$') { throw "no official checksum found for $($item.File)" }
  if (Test-Path $dest) {
    # a .zip image keeps only the extracted .iso (its hash differs from the zip's), so existence is enough
    if ($item.Zip -or (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -eq $item.Sha256) {
      Say " $($item.Name): already here and checked. OK." " $($item.Name): já está aqui e conferido. OK." Green; return $true
    }
  }
  $dl = Join-Path $isoDir ($item.File + $(if ($item.Zip) { '.zip' } else { '' }) + '.part')
  if ((Get-PSDrive $Drive).Free -lt 6GB) { Say " Not enough free space on $Drive`: for $($item.Name)." " Espaço insuficiente em $Drive`: para $($item.Name)." Yellow; return $false }
  Say " Downloading $($item.Name) (resumes if interrupted)..." " Baixando $($item.Name) (continua de onde parou se cair)..."
  & curl.exe -L --fail -C - --retry 5 --retry-delay 5 -o $dl $item.Url
  if ($LASTEXITCODE) { Say " Download failed for $($item.Name) (curl $LASTEXITCODE): run again to resume." " Falha no download de $($item.Name) (curl $LASTEXITCODE): rode de novo para continuar." Yellow; return $false }
  Say ' Checking against the official checksum...' ' Conferindo com o checksum oficial...'
  if ((Get-FileHash $dl -Algorithm SHA256).Hash.ToLower() -ne $item.Sha256) { Remove-Item $dl -Force; Say " $($item.Name) is damaged (checksum mismatch): run again." " $($item.Name) veio corrompido (checksum não bate): rode de novo." Yellow; return $false }
  if ($item.Zip) {
    $x = Join-Path $isoDir ('_x_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive $dl $x -Force
    $inner = Get-ChildItem $x -Recurse -Filter *.iso | Select-Object -First 1
    if (-not $inner) { Remove-Item $x -Recurse -Force; Remove-Item $dl -Force; throw "no .iso inside $($item.File).zip" }
    Move-Item -Force $inner.FullName $dest
    Remove-Item $x -Recurse -Force; Remove-Item $dl -Force
  } else { Move-Item -Force $dl $dest }
  if ($item.Keep) { Get-ChildItem $isoDir -Filter $item.Keep -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $item.File } | ForEach-Object { Remove-Item $_.FullName -Force; Say " removed the older $($_.Name)" " removido o antigo $($_.Name)" } }
  Say " $($item.Name) checked: OK." " $($item.Name) conferido: OK." Green; return $true
}

# ---------------------------------------------------------------- 2. Linux Mint XFCE (always), then optional extras
# each resolver returns @{ Name; File; Url; Sha256; Zip?; Keep? } using the project's current version and checksum
$Images = [ordered]@{
  mint = @{ Always = $true; Resolve = {
    $mirror = 'https://mirrors.edge.kernel.org/linuxmint/stable/'
    $ver = (Invoke-WebRequest $mirror -UseBasicParsing).Links.href | Where-Object { $_ -match '^\d+(\.\d+)?/$' } | ForEach-Object { $_.TrimEnd('/') } | Sort-Object { [version]($_ + $(if ($_ -notmatch '\.') { '.0' })) } | Select-Object -Last 1
    $file = "linuxmint-$ver-xfce-64bit.iso"
    @{ Name = "Linux Mint $ver XFCE"; File = $file; Url = "$mirror$ver/$file"; Keep = 'linuxmint-*-xfce-64bit.iso'
       Sha256 = (Find-Hash (Fetch-Text "$mirror$ver/sha256sum.txt") $file) }
  } }
  systemrescue = @{ Desc = (T 'repair Windows/Linux, recover files, reset a forgotten Windows password (~0.9 GB)' 'reparar Windows/Linux, recuperar arquivos, resetar uma senha esquecida do Windows (~0,9 GB)'); Resolve = {
    $page = (Invoke-WebRequest 'https://www.system-rescue.org/Download/' -UseBasicParsing).Content
    $file = ([regex]::Match($page, 'systemrescue-[\d.]+-amd64\.iso')).Value
    $ver = ([regex]::Match($file, '[\d.]+')).Value
    $base = "https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/$ver"
    @{ Name = "SystemRescue $ver"; File = $file; Url = "$base/$file/download"; Keep = 'systemrescue-*-amd64.iso'
       Sha256 = (Find-Hash (Fetch-Text "$base/$file.sha256" "$base/$file.sha256/download") $file) }
  } }
  rescuezilla = @{ Desc = (T 'back up and restore a whole disk, point and click (~1.3 GB)' 'fazer backup e restaurar um disco inteiro, com cliques (~1,3 GB)'); Resolve = {
    $rel = Invoke-RestMethod 'https://api.github.com/repos/rescuezilla/rescuezilla/releases/latest'
    $iso = @($rel.assets | Where-Object { $_.name -match '64bit\.noble\.iso$' }) + @($rel.assets | Where-Object { $_.name -match '64bit\.[a-z]+\.iso$' }) | Select-Object -First 1
    $shaUrl = ($rel.assets | Where-Object { $_.name -eq 'SHA256SUM' }).browser_download_url
    @{ Name = "Rescuezilla $($rel.tag_name)"; File = $iso.name; Url = $iso.browser_download_url; Keep = 'rescuezilla-*.iso'
       Sha256 = (Find-Hash (Fetch-Text $shaUrl) $iso.name) }
  } }
  memtest = @{ Desc = (T 'test the computer''s memory (RAM) for faults (~20 MB)' 'testar a memória (RAM) do computador (~20 MB)'); Resolve = {
    $page = (Invoke-WebRequest 'https://www.memtest.org/' -UseBasicParsing).Content
    $ver = ([regex]::Match($page, 'download/v([\d.]+)/mt86plus')).Groups[1].Value
    $base = "https://www.memtest.org/download/v$ver"; $zip = "mt86plus_${ver}_x86_64.iso.zip"
    @{ Name = "Memtest86+ $ver"; File = "memtest86plus-$ver.iso"; Url = "$base/$zip"; Zip = $true; Keep = 'memtest86plus-*.iso'
       Sha256 = (Find-Hash (Fetch-Text "$base/sha256sum.txt") $zip) }
  } }
  antix = @{ Desc = (T 'a very light Linux for old or slow computers (~1.5 GB)' 'um Linux bem leve para computadores velhos ou lentos (~1,5 GB)'); Resolve = {
    $list = (Invoke-WebRequest 'https://sourceforge.net/projects/antix-linux/files/Final/' -UseBasicParsing).Content
    $ver = ([regex]::Matches($list, 'antiX-(\d+(?:\.\d+)+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } | Select-Object -Last 1)
    $file = "antiX-${ver}_x64-full.iso"; $base = "https://sourceforge.net/projects/antix-linux/files/Final/antiX-$ver"
    @{ Name = "antiX $ver"; File = $file; Url = "$base/$file/download"; Keep = 'antiX-*_x64-full.iso'
       Sha256 = (Find-Hash (Fetch-Text "$base/$file.sha256/download" "$base/$file.sha256") $file) }
  } }
  kali = @{ Desc = (T 'security testing of YOUR OWN network/devices, e.g. Wi-Fi (permission required) (~4 GB)' 'teste de segurança da SUA PRÓPRIA rede/aparelhos, ex. Wi-Fi (precisa de permissão) (~4 GB)'); Resolve = {
    $sums = Fetch-Text 'https://cdimage.kali.org/current/SHA256SUMS'
    $file = ([regex]::Match($sums, 'kali-linux-[\d.]+-live-amd64\.iso')).Value
    @{ Name = 'Kali Linux (live)'; File = $file; Url = "https://cdimage.kali.org/current/$file"; Keep = 'kali-linux-*-live-amd64.iso'
       Sha256 = (Find-Hash $sums $file) }
  } }
}

function Add-Image($key) {
  try { $item = & $Images[$key].Resolve }
  catch { Say " Could not reach the download site for $key (no internet?). Skipped." " Não deu para acessar o site de download de $key (sem internet?). Pulado." Yellow; return }
  try { [void](Save-Image $item) } catch { Say " $key`: $($_.Exception.Message)" " $key`: $($_.Exception.Message)" Yellow }
}

# Linux Mint always
Add-Image 'mint'

# which extras: -Extras all|none|comma-list, else ask
$opt = @($Images.Keys | Where-Object { -not $Images[$_].Always })
$want = @()
if ($Extras) {
  if ($Extras -eq 'all') { $want = $opt } elseif ($Extras -ne 'none') { $want = @($Extras -split '[,; ]+' | Where-Object { $opt -contains $_ }) }
} elseif (-not $Yes) {
  Write-Host ''
  Say ' Add more systems to the drive? (optional, all free and from their official sites)' ' Adicionar mais sistemas ao pendrive? (opcional, todos gratuitos e dos sites oficiais)' Cyan
  for ($i = 0; $i -lt $opt.Count; $i++) { Write-Host ("   {0}. {1} - {2}" -f ($i + 1), $opt[$i], $Images[$opt[$i]].Desc) }
  Say ' Kali is for testing systems and networks you own or are allowed to test. Using it against others is illegal and your responsibility.' ' O Kali é para testar sistemas e redes que você possui ou tem permissão para testar. Usá-lo contra terceiros é ilegal e de sua responsabilidade.' Yellow
  $pick = Read-Host (T ' Type the numbers you want (e.g. 1 3 5), or Enter to skip' ' Digite os números que quiser (ex.: 1 3 5), ou Enter para pular')
  $want = @($pick -split '[,; ]+' | Where-Object { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $opt.Count } | ForEach-Object { $opt[[int]$_ - 1] } | Select-Object -Unique)
}
foreach ($k in $want) { Add-Image $k }

# ---------------------------------------------------------------- the on-drive guide, listing what is actually there
$present = @(Get-ChildItem $isoDir -Filter *.iso -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$hasKali = [bool]($present | Where-Object { $_ -like 'kali-*' })
$list = ($present | ForEach-Object { "   - $_" }) -join "`r`n"
$kaliEn = if ($hasKali) { "`r`nKali Linux is for testing the security of systems and networks you OWN or have written permission to test`r`n(e.g. your own Wi-Fi). Using it against anything else is illegal and is your responsibility.`r`n" } else { '' }
$kaliPt = if ($hasKali) { "`r`nO Kali Linux serve para testar a segurança de sistemas e redes que você POSSUI ou tem permissão por escrito`r`npara testar (ex.: o seu próprio Wi-Fi). Usá-lo contra qualquer outra coisa é ilegal e de sua responsabilidade.`r`n" } else { '' }
[IO.File]::WriteAllText((Join-Path $isoDir 'READ-ME.txt'), @"
Starting a computer from this drive (Survival Station).
1. Plug in the drive and turn the computer on, pressing its boot-menu key: usually F12, F11, F9, F8 or Esc
   (Apple Intel Macs: hold Option). Choose the USB drive.
2. In the Ventoy menu, choose a system below and "Boot in normal mode".
3. First time on a computer with Secure Boot: Ventoy asks you to enroll its key once; follow the screens.
4. In Linux Mint: open the file manager, open the SURVIVAL drive and run:  bash START-LINUX.sh
Nothing is installed on the computer unless you choose to install it.

Systems on this drive:
$list
$kaliEn
Iniciar um computador por este pendrive (Survival Station).
1. Conecte o pendrive e ligue o computador apertando a tecla do menu de boot: geralmente F12, F11, F9, F8 ou Esc
   (Mac Intel: segure Option). Escolha o pendrive.
2. No menu do Ventoy, escolha um sistema da lista acima e "Boot in normal mode".
3. Na primeira vez num computador com Secure Boot: o Ventoy pede para registrar a chave uma vez; siga as telas.
4. No Linux Mint: abra o gerenciador de arquivos, abra o pendrive SURVIVAL e rode:  bash START-LINUX.sh
Nada é instalado no computador, a não ser que você escolha instalar.
$kaliPt
"@, (New-Object Text.UTF8Encoding $false))

Write-Host ''
Say " Done: $($Drive): can now start a computer. Systems: $($present -join ', ')" " Pronto: $($Drive): agora inicia um computador. Sistemas: $($present -join ', ')" Green
Say ' Run MAKE-BOOTABLE.bat again any time to add more systems or update them (it erases nothing once the drive is bootable).' ' Rode o MAKE-BOOTABLE.bat de novo quando quiser para adicionar ou atualizar sistemas (não apaga nada depois que o pendrive já é inicializável).'
Say ' The kit''s files go on this same drive as usual (COPY-KIT.bat or MAKE-USB.bat). How to start from it: ISO\READ-ME.txt and the Help page.' ' Os arquivos do kit vão neste mesmo pendrive, como sempre (COPY-KIT.bat ou MAKE-USB.bat). Como iniciar por ele: ISO\READ-ME.txt e a página de Ajuda.'
