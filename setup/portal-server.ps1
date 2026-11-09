<#
.SYNOPSIS
  A tiny static web server for the portal pages, used when the kit is started WITHOUT the AI. Normally the AI
  program (llama-server --path portal) serves the pages; with no AI, this serves them instead, so the library,
  offline map, search, cards and the rest still work over http://localhost:8080.

  This computer only (localhost / 127.0.0.1): phones need the AI mode, because serving to the whole network needs
  administrator rights. Supports HTTP range requests, so the offline map (PMTiles) loads. Started by
  START-WINDOWS.bat for the "No AI" choice; stopped when the kit shuts down.
#>
param([Parameter(Mandatory)][string]$Root, [int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$dir = (Resolve-Path (Join-Path $Root 'portal')).Path.TrimEnd('\')
$mime = @{
  '.html' = 'text/html; charset=utf-8'; '.htm' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'
  '.mjs' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.json' = 'application/json; charset=utf-8'
  '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'
  '.webp' = 'image/webp'; '.ico' = 'image/x-icon'; '.pmtiles' = 'application/octet-stream'; '.pbf' = 'application/octet-stream'
  '.mvt' = 'application/octet-stream'; '.bin' = 'application/octet-stream'; '.wasm' = 'application/wasm'
  '.csv' = 'text/csv; charset=utf-8'; '.txt' = 'text/plain; charset=utf-8'; '.pdf' = 'application/pdf'
  '.woff' = 'font/woff'; '.woff2' = 'font/woff2'; '.webmanifest' = 'application/manifest+json'
}

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try { $listener.Start() } catch { exit 0 }   # port already in use: something else serves it

while ($listener.IsListening) {
  try { $ctx = $listener.GetContext() } catch { break }
  try {
    $req = $ctx.Request; $res = $ctx.Response
    $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
    if ($rel -eq '') { $rel = 'index.html' }
    # the AI's own endpoints: there is no AI in this mode, so answer 503 and flag it, and the pages show the
    # AI as off (not "still loading") and keep the library, maps, search and cards working
    if ($rel -in 'health', 'props', 'tokenize', 'embedding', 'embeddings' -or $rel -like 'v1/*' -or $rel -like 'completion*') {
      $res.StatusCode = 503; $res.Headers['X-Survival-No-AI'] = '1'; $res.Headers['Access-Control-Allow-Origin'] = '*'; $res.Close(); continue
    }
    $full = try { [IO.Path]::GetFullPath((Join-Path $dir $rel)) } catch { '' }
    # stay inside the portal folder (no ../ escaping), serve files only
    if (-not $full -or -not ($full.StartsWith($dir + '\', [StringComparison]::OrdinalIgnoreCase) -or $full -eq $dir)) { $res.StatusCode = 403; $res.Close(); continue }
    if (Test-Path $full -PathType Container) { $full = Join-Path $full 'index.html' }
    if (-not (Test-Path $full -PathType Leaf)) { $res.StatusCode = 404; $res.Close(); continue }
    $ct = $mime[[IO.Path]::GetExtension($full).ToLower()]; if (-not $ct) { $ct = 'application/octet-stream' }
    $res.ContentType = $ct
    $res.Headers['Cache-Control'] = 'no-cache'
    $res.Headers['Access-Control-Allow-Origin'] = '*'
    $res.Headers['Accept-Ranges'] = 'bytes'
    $fs = [IO.File]::OpenRead($full)
    try {
      $len = $fs.Length; $start = 0L; $count = $len
      $range = $req.Headers['Range']
      if ($range -and $range -match 'bytes=(\d*)-(\d*)') {
        $a = $Matches[1]; $b = $Matches[2]
        if ($a -ne '') { $start = [int64]$a; $end = if ($b -ne '') { [int64]$b } else { $len - 1 } }
        else { $start = $len - [int64]$b; $end = $len - 1 }
        if ($start -lt 0) { $start = 0 }
        if ($end -ge $len) { $end = $len - 1 }
        if ($start -gt $end -or $start -ge $len) { $res.StatusCode = 416; $res.Headers['Content-Range'] = "bytes */$len"; $res.Close(); continue }
        $count = $end - $start + 1
        $res.StatusCode = 206
        $res.Headers['Content-Range'] = "bytes $start-$end/$len"
      }
      $res.ContentLength64 = $count
      if ($req.HttpMethod -ne 'HEAD') {
        $fs.Position = $start
        $buf = New-Object byte[] 65536; $left = $count
        while ($left -gt 0) {
          $read = $fs.Read($buf, 0, [int][Math]::Min($buf.Length, $left))
          if ($read -le 0) { break }
          $res.OutputStream.Write($buf, 0, $read); $left -= $read
        }
      }
    } finally { $fs.Close() }
    $res.Close()
  } catch { try { $ctx.Response.Abort() } catch { } }
}
