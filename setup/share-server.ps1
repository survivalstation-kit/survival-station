<#
.SYNOPSIS
  Shared map pins for everyone on the kit's Wi-Fi or hotspot: water, shelter, meeting points, dangers...
  Started by START-WINDOWS.bat next to the AI server; stops by itself when the AI server stops.

  Listens on every network address (port 8094), so phones can reach it. Windows' HttpListener would need
  administrator rights for that, so this answers plain HTTP itself over a TcpListener: one small request at a
  time, JSON only. Only the kit's own pages may use it (their Origin ends in :8080 or :8443).
    GET  /pins          -> { pins: [...] }
    POST /pins          { lat, lon, type, label, note }  -> adds one
    POST /pins/delete   { id }                           -> removes one
  The pins are kept on the kit in my-data\pins.json.
#>
param([Parameter(Mandatory)][string]$Root, [int]$Port = 8094, [string]$WatchProcess = 'llama-server')   # stops when this program is gone
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$File = Join-Path $Root 'my-data\pins.json'
$Types = 'water', 'shelter', 'meet', 'danger', 'medical', 'food', 'power', 'other'
$MaxPins = 500
$utf8 = New-Object Text.UTF8Encoding $false

function Load-Pins { if (Test-Path $File) { try { @(([IO.File]::ReadAllText($File) | ConvertFrom-Json).pins) } catch { @() } } else { @() } }
function Save-Pins($pins) {
  New-Item -ItemType Directory -Force (Split-Path $File) | Out-Null
  [IO.File]::WriteAllText($File, (ConvertTo-Json -Compress -Depth 4 -InputObject @{ pins = @($pins) }), $utf8)
}
function Clean([string]$s, [int]$max) { $s = ($s -replace '[\x00-\x1f]', ' ').Trim(); if ($s.Length -gt $max) { $s.Substring(0, $max) } else { $s } }

function Reply($stream, [int]$code, $body, $origin) {
  $json = if ($body -is [string]) { $body } else { ConvertTo-Json -Compress -Depth 4 -InputObject $body }
  $bytes = $utf8.GetBytes($json)
  $status = @{ 200 = 'OK'; 204 = 'No Content'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found'; 413 = 'Too Large'; 507 = 'Full' }[$code]
  $head = "HTTP/1.1 $code $status`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n"
  if ($origin) { $head += "Access-Control-Allow-Origin: $origin`r`nVary: Origin`r`nAccess-Control-Allow-Methods: GET, POST`r`nAccess-Control-Allow-Headers: Content-Type`r`n" }
  $h = [Text.Encoding]::ASCII.GetBytes($head + "`r`n")
  $stream.Write($h, 0, $h.Length); if ($code -ne 204) { $stream.Write($bytes, 0, $bytes.Length) }
}

function Handle($client) {
  $client.ReceiveTimeout = 5000; $client.SendTimeout = 5000
  $stream = $client.GetStream()
  # the request line and headers, up to the blank line
  $buf = New-Object byte[] 8192; $got = 0; $end = -1
  while ($end -lt 0 -and $got -lt $buf.Length) {
    $n = $stream.Read($buf, $got, $buf.Length - $got); if ($n -le 0) { return }
    $got += $n
    $text = [Text.Encoding]::ASCII.GetString($buf, 0, $got); $end = $text.IndexOf("`r`n`r`n")
  }
  if ($end -lt 0) { Reply $stream 413 @{ error = 'too large' } $null; return }
  $lines = $text.Substring(0, $end) -split "`r`n"
  $method, $target = $lines[0] -split ' '
  $hdr = @{}; foreach ($l in $lines[1..($lines.Count - 1)]) { $i = $l.IndexOf(':'); if ($i -gt 0) { $hdr[$l.Substring(0, $i).Trim().ToLower()] = $l.Substring($i + 1).Trim() } }
  $origin = $hdr['origin']
  # only the kit's own pages: http on the portal port, or the secure address (Caddy passes /share/* here)
  if (-not $origin -or $origin -notmatch '^https?://[^/]+:(8080|8443)$') { Reply $stream 403 @{ error = 'forbidden' } $null; return }
  $len = [int]("0" + $hdr['content-length'])
  if ($len -gt 4096) { Reply $stream 413 @{ error = 'too large' } $origin; return }
  $bodyBytes = New-Object byte[] $len; $have = $got - $end - 4
  if ($have -gt 0) { [Array]::Copy($buf, $end + 4, $bodyBytes, 0, [Math]::Min($have, $len)) }
  while ($have -lt $len) { $n = $stream.Read($bodyBytes, $have, $len - $have); if ($n -le 0) { break }; $have += $n }
  $path = ($target -split '\?')[0].TrimEnd('/')

  if ($method -eq 'OPTIONS') { Reply $stream 204 '' $origin; return }
  if ($method -eq 'GET' -and $path -eq '/pins') { Reply $stream 200 @{ pins = @(Load-Pins) } $origin; return }
  if ($method -eq 'POST' -and $path -in '/pins', '/pins/delete') {
    $b = try { $utf8.GetString($bodyBytes) | ConvertFrom-Json } catch { $null }
    if (-not $b) { Reply $stream 400 @{ error = 'not JSON' } $origin; return }
    $pins = @(Load-Pins)
    if ($path -eq '/pins/delete') {
      $pins = @($pins | Where-Object { $_.id -ne "$($b.id)" }); Save-Pins $pins
      Reply $stream 200 @{ pins = $pins } $origin; return
    }
    $lat = 0.0; $lon = 0.0
    if (-not [double]::TryParse("$($b.lat)", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$lat) -or
        -not [double]::TryParse("$($b.lon)", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$lon) -or
        [Math]::Abs($lat) -gt 90 -or [Math]::Abs($lon) -gt 180) { Reply $stream 400 @{ error = 'bad position' } $origin; return }
    if ($pins.Count -ge $MaxPins) { Reply $stream 507 @{ error = 'full' } $origin; return }
    $type = if ($Types -contains "$($b.type)") { "$($b.type)" } else { 'other' }
    $pin = [ordered]@{ id = [guid]::NewGuid().ToString('N').Substring(0, 12); lat = [Math]::Round($lat, 6); lon = [Math]::Round($lon, 6)
                       type = $type; label = (Clean "$($b.label)" 60); note = (Clean "$($b.note)" 200); at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    $pins += [pscustomobject]$pin; Save-Pins $pins
    Reply $stream 200 @{ pins = $pins } $origin; return
  }
  Reply $stream 404 @{ error = 'not found' } $origin
}

$listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Any, $Port)
try { $listener.Start() } catch { exit 0 }   # port taken: another kit's share server already runs
$lastCheck = Get-Date
while ($true) {
  if (-not $listener.Pending()) {
    Start-Sleep -Milliseconds 100
    if (((Get-Date) - $lastCheck).TotalSeconds -ge 5) {
      $lastCheck = Get-Date
      if (-not (Get-Process $WatchProcess -ErrorAction SilentlyContinue)) { $listener.Stop(); exit 0 }   # the kit was shut down
    }
    continue
  }
  $client = $listener.AcceptTcpClient()
  try { Handle $client } catch { } finally { $client.Close() }
}
