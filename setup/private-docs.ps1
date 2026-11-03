<#
.SYNOPSIS
  Survival Station private documents: IDs, insurance papers, the family plan. They live in the kit's private\
  folder, outside the portal, so phones on the hotspot never see them, and can be locked with a password.

  Locking encrypts each file to <name>.locked in OpenSSL's format, so a Mac or Linux computer can open them
  with no extra software (launch/private-docs.sh, or by hand):
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -in FILE.locked -out FILE
  Opening decrypts copies into a folder on this computer (never back onto the stick); closing deletes them,
  optionally saving changed copies back, locked.

  PRIVATE-DOCS.bat runs this with -Kit <folder> -Do lock / open / close. kit-control.ps1 dot-sources it (no -Do)
  for the My kit page and the family plan, so these parameters must not share a name with the helper's own
  variables ($Root): dot-sourcing sets them in the helper too.
#>
param([string]$Kit = '', [ValidateSet('', 'lock', 'open', 'close')][string]$Do = '')

$PrivIter = 200000
$PrivCheck = '.password-check.locked'   # a known text, locked with the kit's password, to tell a wrong one
$PrivOpened = Join-Path $env:TEMP 'survival-private'
$PrivMagic = [Text.Encoding]::ASCII.GetBytes('Salted__')

function Get-PrivateDir($root) { Join-Path $root 'private' }

function Get-PrivKey([string]$password, [byte[]]$salt) {
  $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes ([Text.Encoding]::UTF8.GetBytes($password)), $salt, $PrivIter, ([Security.Cryptography.HashAlgorithmName]::SHA256)
  $kiv = $kdf.GetBytes(48)
  $aes = [Security.Cryptography.Aes]::Create()
  $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $kiv[0..31]; $aes.IV = $kiv[32..47]
  $aes
}
# (the leading commas return each byte array whole: PowerShell would otherwise send it on byte by byte, very slowly)
function Protect-Bytes([byte[]]$plain, [string]$password) {
  $salt = New-Object byte[] 8
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
  $enc = (Get-PrivKey $password $salt).CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)
  $ms = New-Object IO.MemoryStream
  $ms.Write($PrivMagic, 0, 8); $ms.Write($salt, 0, 8); $ms.Write($enc, 0, $enc.Length)
  , $ms.ToArray()
}
function Unprotect-Bytes([byte[]]$data, [string]$password) {
  if ($data.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($data, 0, 8) -ne 'Salted__') { throw 'not a locked file' }
  $salt = New-Object byte[] 8
  [Array]::Copy($data, 8, $salt, 0, 8)
  $dec = (Get-PrivKey $password $salt).CreateDecryptor()
  try { , $dec.TransformFinalBlock($data, 16, $data.Length - 16) } catch { throw 'wrong password' }
}

# the password is right if it opens the check file; with no check file yet, any password starts the kit's lock
function Test-PrivatePassword($root, [string]$password) {
  $check = Join-Path (Get-PrivateDir $root) $PrivCheck
  if (-not (Test-Path $check)) { return $null }
  try { [Text.Encoding]::UTF8.GetString((Unprotect-Bytes ([IO.File]::ReadAllBytes($check)) $password)) -eq 'survival-station-private' } catch { $false }
}
function Assert-PrivatePassword($root, [string]$password) {
  if (-not $password) { throw 'Type the password.' }
  $ok = Test-PrivatePassword $root $password
  if ($ok -eq $false) { throw 'Wrong password (it must be the one these files were locked with).' }
  if ($ok -eq $null) {
    if ($password.Length -lt 6) { throw 'Choose a password of at least 6 characters.' }
    New-Item -ItemType Directory -Force (Get-PrivateDir $root) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path (Get-PrivateDir $root) $PrivCheck), (Protect-Bytes ([Text.Encoding]::UTF8.GetBytes('survival-station-private')) $password))
  }
}

# (Test-Path first: PowerShell 5.1's Get-ChildItem -Recurse on a missing folder searches the whole folder above it
#  for that name, which on a kit means the entire drive)
function Get-RecursiveFiles($dir) { if (Test-Path -LiteralPath $dir) { @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue) } else { @() } }
function Get-PrivateFiles($root) {   # every file in private\ (and its subfolders), apart from the check file
  @(Get-RecursiveFiles (Get-PrivateDir $root) | Where-Object { $_.Name -ne $PrivCheck })
}
function Get-PrivateStatus($root) {
  $files = Get-PrivateFiles $root
  [ordered]@{
    locked = @($files | Where-Object { $_.Extension -eq '.locked' }).Count
    plain = @($files | Where-Object { $_.Extension -ne '.locked' } | ForEach-Object { $_.FullName.Substring((Get-PrivateDir $root).Length + 1) })
    hasPassword = Test-Path (Join-Path (Get-PrivateDir $root) $PrivCheck)
    opened = @(Get-RecursiveFiles $PrivOpened | Where-Object { $_.Name -ne '.opened.json' }).Count
    folder = Get-PrivateDir $root
  }
}

# lock every plain file in private\: <name>.locked, checked by opening it again, then the plain file is deleted
function Lock-Private($root, [string]$password) {
  Assert-PrivatePassword $root $password
  $n = 0
  foreach ($f in (Get-PrivateFiles $root | Where-Object { $_.Extension -ne '.locked' })) {
    $plain = [IO.File]::ReadAllBytes($f.FullName)
    $locked = Protect-Bytes $plain $password
    $out = $f.FullName + '.locked'
    [IO.File]::WriteAllBytes($out, $locked)
    $back = Unprotect-Bytes ([IO.File]::ReadAllBytes($out)) $password
    $sha = [Security.Cryptography.SHA256]::Create()
    if ([Convert]::ToBase64String($sha.ComputeHash($back)) -ne [Convert]::ToBase64String($sha.ComputeHash($plain))) { Remove-Item -LiteralPath $out -Force; throw "Locking $($f.Name) failed; it was left as it is." }
    # overwrite before deleting (a flash drive may still keep old copies of the blocks, so lock early)
    [IO.File]::WriteAllBytes($f.FullName, (New-Object byte[] $plain.Length))
    Remove-Item -LiteralPath $f.FullName -Force
    $n++
  }
  $n
}

# a single locked file into a string or bytes (the family plan)
function Read-PrivateFile($root, [string]$name, [string]$password) {
  Assert-PrivatePassword $root $password
  $p = Join-Path (Get-PrivateDir $root) "$name.locked"
  if (-not (Test-Path $p)) { return $null }
  , (Unprotect-Bytes ([IO.File]::ReadAllBytes($p)) $password)
}
function Write-PrivateFile($root, [string]$name, [byte[]]$bytes, [string]$password) {
  Assert-PrivatePassword $root $password
  [IO.File]::WriteAllBytes((Join-Path (Get-PrivateDir $root) "$name.locked"), (Protect-Bytes $bytes $password))
}

# decrypt every locked file into a folder on this computer and remember when, to find changed copies later
function Open-Private($root, [string]$password) {
  if (-not (Get-PrivateStatus $root).hasPassword) { throw 'Nothing is locked on this kit yet.' }
  Assert-PrivatePassword $root $password
  $dir = Get-PrivateDir $root
  if (Test-Path $PrivOpened) { Remove-Item -Recurse -Force $PrivOpened }
  New-Item -ItemType Directory -Force $PrivOpened | Out-Null
  $seen = @{}
  foreach ($f in (Get-PrivateFiles $root | Where-Object { $_.Extension -eq '.locked' })) {
    $rel = $f.FullName.Substring($dir.Length + 1) -replace '\.locked$', ''
    $out = Join-Path $PrivOpened $rel
    New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
    [IO.File]::WriteAllBytes($out, (Unprotect-Bytes ([IO.File]::ReadAllBytes($f.FullName)) $password))
    $seen[$rel] = (Get-Item $out).LastWriteTimeUtc.Ticks
  }
  [IO.File]::WriteAllText((Join-Path $PrivOpened '.opened.json'), (ConvertTo-Json $seen -Compress))
  $PrivOpened
}

# delete the opened copies; with $save, copies changed since opening (and new files) are locked back onto the kit first
function Close-Private($root, [string]$password, [bool]$save) {
  if (-not (Test-Path $PrivOpened)) { return @() }
  $changed = @()
  $seen = @{}
  try { (Get-Content (Join-Path $PrivOpened '.opened.json') -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $seen[$_.Name] = [int64]$_.Value } } catch { }
  foreach ($f in Get-ChildItem $PrivOpened -Recurse -File | Where-Object { $_.Name -ne '.opened.json' }) {
    $rel = $f.FullName.Substring($PrivOpened.Length + 1)
    if (-not $seen.ContainsKey($rel) -or $f.LastWriteTimeUtc.Ticks -ne $seen[$rel]) { $changed += $rel }
  }
  if ($changed -and $save) {
    Assert-PrivatePassword $root $password
    foreach ($rel in $changed) {
      $out = Join-Path (Get-PrivateDir $root) "$rel.locked"
      New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
      [IO.File]::WriteAllBytes($out, (Protect-Bytes ([IO.File]::ReadAllBytes((Join-Path $PrivOpened $rel))) $password))
    }
  }
  if ($changed -and -not $save) { return $changed }   # ask first: these would be lost
  Remove-Item -Recurse -Force $PrivOpened
  @()
}

# ---------------------------------------------------------------- PRIVATE-DOCS.bat
if ($Do) {
  $ErrorActionPreference = 'Stop'
  $Root = (Resolve-Path $Kit).Path.TrimEnd('\') + '\'
  function Ask-Password([string]$prompt) {
    $s = Read-Host $prompt -AsSecureString
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
  }
  try {
    $st = Get-PrivateStatus $Root
    switch ($Do) {
      'lock' {
        if (-not $st.plain.Count) { Write-Host "`n   Nothing to lock. Put your documents in $($st.folder) first." -ForegroundColor Yellow; break }
        Write-Host "`n   Files to lock: $($st.plain -join ', ')"
        $pw = Ask-Password '   Password / Senha'
        if (-not $st.hasPassword) {
          if ((Ask-Password '   Same password again / Repita a senha') -ne $pw) { throw 'The two passwords are different.' }
          Write-Host '   Write the password down and keep it somewhere safe: without it the files can''t be opened.' -ForegroundColor Yellow
        }
        $n = Lock-Private $Root $pw
        Write-Host "`n   Locked $n file(s)." -ForegroundColor Green
      }
      'open' {
        $pw = Ask-Password '   Password / Senha'
        $dir = Open-Private $Root $pw
        Write-Host "`n   Opened on this computer in: $dir" -ForegroundColor Green
        Write-Host '   When you finish, choose "Close" so the copies are deleted from this computer.'
        Start-Process explorer.exe $dir
      }
      'close' {
        $left = Close-Private $Root '' $false
        if ($left.Count) {
          Write-Host "`n   Changed or new since opening: $($left -join ', ')"
          if ((Read-Host '   Save them back to the kit, locked? [Y/n]') -notmatch '^n') {
            $pw = Ask-Password '   Password / Senha'
            [void](Close-Private $Root $pw $true)
          } elseif ((Read-Host '   Delete them without saving? [y/N]') -match '^y') { Remove-Item -Recurse -Force $PrivOpened }
          else { Write-Host '   Left open.'; break }
        }
        Write-Host "`n   Closed: the opened copies were deleted from this computer." -ForegroundColor Green
      }
    }
  } catch { Write-Host "`n   $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
}
