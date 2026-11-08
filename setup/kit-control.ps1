<#
.SYNOPSIS
  Survival Station kit helper. START-WINDOWS.bat runs it next to the AI server so the portal's "My kit" page
  can show what is on the kit and open the builder window (add more, check for updates, verify / repair).

  Listens on this computer only (localhost:8091) and answers only the kit's own pages (Origin check).
  Stops by itself when the AI server stops.
#>
param([Parameter(Mandatory)][string]$Root, [int]$Port = 8091, [int]$PortalPort = 8080)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path.TrimEnd('\') + '\'
. (Join-Path $PSScriptRoot 'private-docs.ps1')   # private documents and the family plan (functions only)
$Allowed = "http://localhost:$PortalPort", "http://127.0.0.1:$PortalPort"
$PS = Join-Path $PSHOME 'powershell.exe'

function Get-Files($dir, $filter) {
  @(Get-ChildItem (Join-Path $Root $dir) -Filter $filter -File -ErrorAction SilentlyContinue | Sort-Object Name |
    ForEach-Object { [ordered]@{ name = $_.Name; size = $_.Length } })
}

function Get-Status {
  # DriveInfo, not Get-Volume: that loads the Storage module first, about 10 seconds on the first call
  $vol = try { New-Object IO.DriveInfo ($Root.Substring(0, 1)) } catch { $null }
  $progress = $null
  $pf = Join-Path $Root 'logs\progress.json'
  if (Test-Path $pf) {
    try { $p = [IO.File]::ReadAllText($pf) | ConvertFrom-Json; if (((Get-Date) - [datetime]$p.updated).TotalHours -lt 12) { $progress = $p } } catch { }
  }
  [ordered]@{
    root = $Root; free = $vol.AvailableFreeSpace; size = $vol.TotalSize; usb = "$($vol.DriveType)" -eq 'Removable'
    models = Get-Files 'models' '*.gguf'
    books = Get-Files 'library' '*.zim'
    maps = Get-Files 'portal\maps' '*.pmtiles'
    partial = @(Get-ChildItem $Root -Recurse -File -Filter *.part -ErrorAction SilentlyContinue | ForEach-Object { [ordered]@{ name = $_.Name -replace '\.part$', ''; size = $_.Length } })
    survivalData = Test-Path (Join-Path $Root 'portal\survival-data\index.html')
    apps = Test-Path (Join-Path $Root 'apps\android')
    choices = Test-Path (Join-Path $Root 'BUILD-CHOICES.txt')
    canBuild = Test-Path (Join-Path $Root 'setup\builder-gui.ps1')
    progress = $progress
    private = Get-PrivateStatus $Root
  }
}

function Read-Body($req) {   # the JSON a page sent
  $r = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
  $text = $r.ReadToEnd()
  if ($text) { $text | ConvertFrom-Json } else { [pscustomobject]@{} }
}

function Send($ctx, $code, $body, $origin) {
  $r = $ctx.Response
  $r.StatusCode = $code
  if ($origin) { $r.Headers['Access-Control-Allow-Origin'] = $origin; $r.Headers['Vary'] = 'Origin' }
  $r.Headers['Cache-Control'] = 'no-store'
  $r.ContentType = 'application/json; charset=utf-8'
  $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 4 -Compress))
  $r.OutputStream.Write($bytes, 0, $bytes.Length)
  $r.Close()
}

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try { $listener.Start() } catch { exit 0 }   # port taken: another kit's helper already runs

while ($true) {
  $task = $listener.GetContextAsync()
  while (-not $task.Wait(5000)) {
    if (-not (Get-Process llama-server -ErrorAction SilentlyContinue)) { $listener.Stop(); exit 0 }   # the kit was shut down
  }
  $ctx = $task.Result
  $req = $ctx.Request
  $origin = $req.Headers['Origin']
  try {
    # only the kit's own pages; anything else (another website in the same browser) is refused
    if ($origin -and $Allowed -notcontains $origin) { Send $ctx 403 @{ error = 'forbidden' } $null; continue }
    $path = $req.Url.AbsolutePath.TrimEnd('/')
    if ($req.HttpMethod -eq 'OPTIONS' -and $origin) {
      # the browser asks first before a page posts JSON (CORS preflight); only the kit's pages get this far
      $r = $ctx.Response
      $r.StatusCode = 204
      $r.Headers['Access-Control-Allow-Origin'] = $origin; $r.Headers['Vary'] = 'Origin'
      $r.Headers['Access-Control-Allow-Methods'] = 'GET, POST'; $r.Headers['Access-Control-Allow-Headers'] = 'Content-Type'
      $r.Close()
    }
    elseif ($req.HttpMethod -eq 'GET' -and $path -eq '/status') { Send $ctx 200 (Get-Status) $origin }
    elseif ($req.HttpMethod -eq 'POST' -and $path -eq '/open' -and $origin) {
      $action = $req.QueryString['action']
      if ($action -notin 'add', 'updates', 'verify') { Send $ctx 400 @{ error = 'unknown action' } $origin; continue }
      $gui = Join-Path $Root 'setup\builder-gui.ps1'
      Start-Process $PS -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Kit "{1}." -Action {2}' -f $gui, $Root, $action)
      Send $ctx 200 @{ ok = $true } $origin
    }
    # the home page's "Shut down the kit": closes the servers and the start window (this helper then stops by itself)
    elseif ($req.HttpMethod -eq 'POST' -and $path -eq '/shutdown' -and $origin) {
      Send $ctx 200 @{ ok = $true } $origin
      Start-Process $PS -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Quiet' -f (Join-Path $PSScriptRoot 'stop-old-kit.ps1'))
    }
    # the user's own lists (checklists, supplies), kept on the stick so they travel with the kit: my-data\<name>.json
    elseif ($path -eq '/data' -and $origin) {
      $name = "$($req.QueryString['name'])"
      if ($name -notmatch '^[a-z][a-z0-9-]{0,30}$') { Send $ctx 400 @{ error = 'bad name' } $origin; continue }
      $file = Join-Path $Root "my-data\$name.json"
      # kept and returned exactly as the page sent it (PowerShell's JSON conversion would flatten deep lists)
      if ($req.HttpMethod -eq 'GET') {
        $text = if (Test-Path $file) { [IO.File]::ReadAllText($file) } else { 'null' }
        $r = $ctx.Response; $r.StatusCode = 200; $r.Headers['Access-Control-Allow-Origin'] = $origin; $r.Headers['Vary'] = 'Origin'; $r.Headers['Cache-Control'] = 'no-store'
        $r.ContentType = 'application/json; charset=utf-8'; $bytes = [Text.Encoding]::UTF8.GetBytes($text); $r.OutputStream.Write($bytes, 0, $bytes.Length); $r.Close()
      }
      elseif ($req.HttpMethod -eq 'POST') {
        $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8); $text = $sr.ReadToEnd()
        if ($text.Length -gt 1MB) { Send $ctx 413 @{ error = 'too big' } $origin; continue }
        try { $null = $text | ConvertFrom-Json } catch { Send $ctx 400 @{ error = 'not JSON' } $origin; continue }
        New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
        [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding $false))
        Send $ctx 200 @{ ok = $true } $origin
      }
      else { Send $ctx 405 @{ error = 'method' } $origin }
    }
    # private favorites: the page encrypts them with the user's password before sending; only that encrypted
    # text is kept, at the top of the kit (outside portal\, so phones can never fetch the file)
    elseif ($path -eq '/favorites' -and $origin) {
      $vault = Join-Path $Root 'favorites.vault'
      if ($req.HttpMethod -eq 'GET') { Send $ctx 200 @{ vault = $(if (Test-Path $vault) { [IO.File]::ReadAllText($vault) } else { $null }) } $origin }
      elseif ($req.HttpMethod -eq 'POST') {
        $b = Read-Body $req
        if ("$($b.vault)" -notmatch '^\{"v":1,') { Send $ctx 400 @{ error = 'not an encrypted vault' } $origin }
        else { [IO.File]::WriteAllText($vault, "$($b.vault)", (New-Object Text.UTF8Encoding $false)); Send $ctx 200 @{ ok = $true } $origin }
      }
      else { Send $ctx 405 @{ error = 'method' } $origin }
    }
    # private documents (setup\private-docs.ps1) and the family plan; only the kit's own pages, on this computer
    elseif ($req.HttpMethod -eq 'POST' -and $path -like '/private/*' -and $origin) {
      $b = Read-Body $req
      switch ($path) {
        '/private/lock' { Send $ctx 200 @{ locked = (Lock-Private $Root "$($b.password)") } $origin }
        '/private/open' { $dir = Open-Private $Root "$($b.password)"; Start-Process explorer.exe $dir; Send $ctx 200 @{ folder = $dir } $origin }
        '/private/close' {
          if ($b.discard) { Remove-Item -Recurse -Force $PrivOpened -ErrorAction SilentlyContinue; Send $ctx 200 @{ unsaved = @() } $origin }
          else { Send $ctx 200 @{ unsaved = @(Close-Private $Root "$($b.password)" ([bool]$b.save)) } $origin }
        }
        '/private/show' { New-Item -ItemType Directory -Force (Get-PrivateDir $Root) | Out-Null; Start-Process explorer.exe (Get-PrivateDir $Root); Send $ctx 200 @{ ok = $true } $origin }
        '/private/plan-save' {
          Write-PrivateFile $Root 'family-plan.json' ([Text.Encoding]::UTF8.GetBytes("$($b.json)")) "$($b.password)"
          Write-PrivateFile $Root 'family-plan.html' ([Text.Encoding]::UTF8.GetBytes("$($b.html)")) "$($b.password)"
          Send $ctx 200 @{ ok = $true } $origin
        }
        '/private/plan-load' {
          $bytes = Read-PrivateFile $Root 'family-plan.json' "$($b.password)"
          Send $ctx 200 @{ json = $(if ($bytes) { [Text.Encoding]::UTF8.GetString($bytes) } else { $null }) } $origin
        }
        default { Send $ctx 404 @{ error = 'not found' } $origin }
      }
    }
    else { Send $ctx 404 @{ error = 'not found' } $origin }
  } catch { try { Send $ctx 400 @{ error = "$($_.Exception.Message)" } $origin } catch { } }
}
