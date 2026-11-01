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
$Allowed = "http://localhost:$PortalPort", "http://127.0.0.1:$PortalPort"
$PS = Join-Path $PSHOME 'powershell.exe'

function Get-Files($dir, $filter) {
  @(Get-ChildItem (Join-Path $Root $dir) -Filter $filter -File -ErrorAction SilentlyContinue | Sort-Object Name |
    ForEach-Object { [ordered]@{ name = $_.Name; size = $_.Length } })
}

function Get-Status {
  $vol = Get-Volume -DriveLetter $Root[0] -ErrorAction SilentlyContinue
  $progress = $null
  $pf = Join-Path $Root 'logs\progress.json'
  if (Test-Path $pf) {
    try { $p = [IO.File]::ReadAllText($pf) | ConvertFrom-Json; if (((Get-Date) - [datetime]$p.updated).TotalHours -lt 12) { $progress = $p } } catch { }
  }
  [ordered]@{
    root = $Root; free = $vol.SizeRemaining; size = $vol.Size; usb = $vol.DriveType -eq 'Removable'
    models = Get-Files 'models' '*.gguf'
    books = Get-Files 'library' '*.zim'
    maps = Get-Files 'portal\maps' '*.pmtiles'
    partial = @(Get-ChildItem $Root -Recurse -File -Filter *.part -ErrorAction SilentlyContinue | ForEach-Object { [ordered]@{ name = $_.Name -replace '\.part$', ''; size = $_.Length } })
    survivalData = Test-Path (Join-Path $Root 'portal\survival-data\index.html')
    apps = Test-Path (Join-Path $Root 'apps\android')
    choices = Test-Path (Join-Path $Root 'BUILD-CHOICES.txt')
    canBuild = Test-Path (Join-Path $Root 'setup\builder-gui.ps1')
    progress = $progress
  }
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
    if ($req.HttpMethod -eq 'GET' -and $path -eq '/status') { Send $ctx 200 (Get-Status) $origin }
    elseif ($req.HttpMethod -eq 'POST' -and $path -eq '/open' -and $origin) {
      $action = $req.QueryString['action']
      if ($action -notin 'add', 'updates', 'verify') { Send $ctx 400 @{ error = 'unknown action' } $origin; continue }
      $gui = Join-Path $Root 'setup\builder-gui.ps1'
      Start-Process $PS -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Kit "{1}." -Action {2}' -f $gui, $Root, $action)
      Send $ctx 200 @{ ok = $true } $origin
    }
    else { Send $ctx 404 @{ error = 'not found' } $origin }
  } catch { try { Send $ctx 500 @{ error = "$($_.Exception.Message)" } $origin } catch { } }
}
