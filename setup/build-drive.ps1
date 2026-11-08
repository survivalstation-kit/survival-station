<#
.SYNOPSIS
  Builds an offline survival USB drive: local AI + offline library + survival data.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup\build-drive.ps1 -Drive E: -Tier Lite
  powershell -ExecutionPolicy Bypass -File setup\build-drive.ps1 -Drive E: -Tier Standard
  powershell -ExecutionPolicy Bypass -File setup\build-drive.ps1 -Drive E: -Tier Full -Gutenberg

  powershell -ExecutionPolicy Bypass -File setup\build-drive.ps1 -Drive E: -Languages en,pt -Map brazil

  Re-run any time: finished files are skipped, half-finished downloads resume.

  Tier      Drive size   What you get (English)
  Lite      16 GB+       AI (4B + 1B), medical, water, food, disaster, knots, travel
  Standard  64 GB+       + 8B AI, Wikipedia (mini, ~13 GB), iFixit, MDWiki, Energypedia
  Full      256 GB+      Wikipedia with all pictures (~119 GB) instead of mini
  -Gutenberg adds ~206 GB of public domain books.

  -Languages en,pt   library languages (pt = Português: Lite ~2 GB, Standard ~8 GB, Full ~20 GB extra)
  -Map <names>       detailed street maps, comma separated (a world overview map is always included):
                     brazil, portugal, usa (lower 48), alaska, hawaii, canada, canada-south,
                     or a Brazilian state: rio-grande-do-sul, santa-catarina,
                     parana, sao-paulo, rio-de-janeiro, minas-gerais, bahia, pernambuco
  -MapBbox "minLon,minLat,maxLon,maxLat" -MapName myarea    any other area (find one at bboxfinder.com)
  -MapMaxZoom 15     15 = every street (default); 13 or 14 = about 2-4x smaller

  The builder window (MAKE-USB.bat -> setup\builder-gui.ps1) uses two more options:
  -Catalog list.json   write every model, library book and map with its current size, then stop
  -Items a,b,c         get exactly these (ids from the catalog) instead of a tier
#>
param(
  [string]$Drive = '',
  [ValidateSet('Lite', 'Standard', 'Full')][string]$Tier = 'Lite',
  [string]$Languages = 'en',  # comma separated: en, pt
  [string]$Map = '',
  [string]$MapBbox = '',
  [string]$MapName = 'custom',
  [ValidateRange(8, 15)][int]$MapMaxZoom = 15,
  [switch]$Gutenberg,
  [switch]$Yes,          # don't ask for confirmation
  [switch]$IndexOnly,    # only rebuild the docs and map lists (after adding your own files)
  [string]$Items = '',   # comma separated ids: get exactly these models, books, maps, survival-data, apps
  [string]$Catalog = '', # write all items and their sizes to this JSON file, then stop
  [switch]$Update,       # update what is already on the kit: newer library editions, AI engine, old maps, Survival-Data
  [int]$MapMaxAgeDays = 365,  # with -Update: re-cut maps older than this from the newest map data
  [switch]$Verify,       # check every part of the kit, then offer to refresh app files and re-fetch broken items
  [switch]$Resume,       # build again exactly what BUILD-CHOICES.txt on the drive lists (finish a stopped build)
  # auto = test the drive's write speed and prepare on this computer only what a slow drive would hold up;
  # local = prepare everything on this computer's disk, then copy it to the drive; direct = straight to the drive
  [ValidateSet('auto', 'local', 'direct')][string]$Staging = 'auto'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is 10x slower with the progress bar

# Downloads (curl) and map cutting (pmtiles) run as child programs. They go in a Windows job object that
# kills them when this builder stops for any reason (window closed, Ctrl+C, error), so none keep running
# on their own, writing to the drive.
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class ChildProcesses {
  [StructLayout(LayoutKind.Sequential)] struct Basic { public long A, B; public uint LimitFlags; public UIntPtr C, D; public uint E; public UIntPtr F; public uint G, H; }
  [StructLayout(LayoutKind.Sequential)] struct Io { public ulong A, B, C, D, E, F; }
  [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic Basic; public Io Io; public UIntPtr P, J, PU, JU; }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
  [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
  [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  static IntPtr job = IntPtr.Zero;   // never closed on purpose: Windows closes it when this process ends
  public static bool Add(IntPtr process) {
    if (job == IntPtr.Zero) {
      job = CreateJobObject(IntPtr.Zero, null);
      var info = new Extended(); info.Basic.LimitFlags = 0x2000;   // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
      int length = Marshal.SizeOf(typeof(Extended)); IntPtr p = Marshal.AllocHGlobal(length);
      Marshal.StructureToPtr(info, p, false); SetInformationJobObject(job, 9, p, (uint)length); Marshal.FreeHGlobal(p);
    }
    return AssignProcessToJobObject(job, process);
  }
}
'@
function Add-ChildProcess($p) { try { [void][ChildProcesses]::Add($p.Handle) } catch { } }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# the app's version: portal\version.js is the one place it is set (bump it for every release, see CHANGELOG.md)
function Get-AppVersion($folder) {
  $f = Join-Path $folder 'portal\version.js'
  if ((Test-Path $f) -and ((Get-Content $f -Raw) -match "version:\s*'([^']+)'")) { $Matches[1] } else { '' }
}
$AppVersion = Get-AppVersion $Root

# everything printed (and any error) also goes to logs\build-<time>.log or logs\sizes-<time>.log
$LogDir = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
Get-ChildItem $LogDir -Filter *.log | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force
$Log = Join-Path $LogDir ('{0}-{1:yyyy-MM-dd_HHmmss}.log' -f $(if ($Catalog) { 'sizes' } else { 'build' }), (Get-Date))
try { Start-Transcript -Path $Log | Out-Null } catch { }
trap {
  Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "   at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor Red
  Write-Host "   Log: $Log" -ForegroundColor Red
  Write-Host '   Run the builder again to resume; finished downloads are kept.' -ForegroundColor Red
  if ($script:prog -and $script:prog.Total) { $script:prog.Item = "$($_.Exception.Message)"; try { Show-Progress -Force -State 'error' } catch { } }
  try { Stop-Transcript | Out-Null } catch { }
  exit 1
}
if (-not $Drive -and -not $Catalog) { throw 'Use -Drive E: (the USB drive letter) or -Drive C:\Survival (a folder on this computer)' }
# a folder on this computer works the same as a drive: everything finds its files relative to the start file
if ($Drive -and $Drive.TrimEnd('\').Length -gt 2) { New-Item -ItemType Directory -Force $Drive | Out-Null }
$Target = if ($Drive) { (Resolve-Path ($Drive.TrimEnd('\') + '\')).Path } else { '' }
$Tmp = if ($Target) { Join-Path $Target '.download' } else { Join-Path $env:TEMP 'survival-station' }
# BUILD-CHOICES.txt: what this drive was built with, written before downloading so a stopped build can be finished.
# Readable instructions on top; the lines after $ChoicesMarker are read back by the builder and the builder window.
$ChoicesFile = if ($Target) { Join-Path $Target 'BUILD-CHOICES.txt' }
$ChoicesMarker = '# --- builder data (do not edit) ---'
function Read-Choices {
  if (-not $ChoicesFile -or -not (Test-Path $ChoicesFile)) { return }
  $data = @{}
  $lines = Get-Content $ChoicesFile -Encoding UTF8
  $at = [array]::IndexOf($lines, $ChoicesMarker)
  if ($at -lt 0) { return }
  foreach ($l in $lines[($at + 1)..($lines.Count - 1)]) { if ($l -match '^(\w+)=(.*)$') { $data[$Matches[1]] = $Matches[2].Trim() } }
  $c = @{ Items = @("$($data.items)".Split(',', [StringSplitOptions]::RemoveEmptyEntries)); Zoom = 15 }
  if ($data.zoom -match '^\d+$') { $c.Zoom = [int]$data.zoom }
  if ($data.custom -match '^([^|]+)\|([^|]+)(\|(\d+))?$') { $c.Custom = @{ Name = $Matches[1]; Bbox = $Matches[2]; Size = [int64]("0$($Matches[4])") } }
  $c
}
if ($Resume) {
  $ch = Read-Choices
  if (-not $ch) { throw "No BUILD-CHOICES.txt in $Target. Build the drive from the builder window first." }
  $Items = $ch.Items -join ','
  $MapMaxZoom = $ch.Zoom
  if ($ch.Custom) { $MapBbox = $ch.Custom.Bbox; $MapName = $ch.Custom.Name }
}
$ItemSet = @($Items.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().ToLower() })

# ---------------------------------------------------------------- content lists

$Models = @(
  @{ Id = 'qwen3-4b'; Tier = 'Lite'; Name = 'Qwen3-4B (recommended)'; File = 'Qwen_Qwen3-4B-Q4_K_M.gguf'
     Url = 'https://huggingface.co/bartowski/Qwen_Qwen3-4B-GGUF/resolve/main/Qwen_Qwen3-4B-Q4_K_M.gguf' }
  @{ Id = 'llama-3.2-1b'; Tier = 'Lite'; Name = 'Llama-3.2-1B (old or slow computers)'; File = 'Llama-3.2-1B-Instruct-Q4_K_M.gguf'
     Url = 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf' }
  @{ Id = 'qwen3-8b'; Tier = 'Standard'; Name = 'Qwen3-8B (smarter, needs 8 GB+ RAM)'; File = 'Qwen_Qwen3-8B-Q4_K_M.gguf'
     Url = 'https://huggingface.co/bartowski/Qwen_Qwen3-8B-GGUF/resolve/main/Qwen_Qwen3-8B-Q4_K_M.gguf' }
  # Mmproj: the vision part, saved as models\mmproj\<File>; the start files load it with the model (--mmproj)
  @{ Id = 'gemma3-4b-vision'; Tier = 'Standard'; Name = 'Gemma 3 4B (looks at photos)'; File = 'gemma-3-4b-it-Q4_K_M.gguf'
     Url = 'https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf'
     Mmproj = 'https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/mmproj-model-f16.gguf' }
)
function Get-MmprojPath($m) { Join-Path $Target "models\mmproj\$($m.File)" }

# Kiwix ZIM archives: folder on download.kiwix.org/zim/ + file prefix (newest date is picked automatically)
# NotIn = skip in that tier because a bigger edition replaces it; Opt = only with its switch (-Gutenberg)
$Zims = @(
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'other'; Prefix = 'zimgit-medicine_en'; Name = 'Medicine: first aid and common illnesses' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'other'; Prefix = 'zimgit-water_en'; Name = 'Water: finding and purifying it' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'other'; Prefix = 'zimgit-food-preparation_en'; Name = 'Food preparation and storage' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'other'; Prefix = 'zimgit-post-disaster_en'; Name = 'After a disaster: shelter, sanitation, recovery' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'other'; Prefix = 'zimgit-knots_en'; Name = 'Knots' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'other'; Prefix = 'appropedia_en_all_maxi'; Name = 'Appropedia: low-tech and DIY solutions' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'wikipedia'; Prefix = 'wikipedia_en_medicine_maxi'; Name = 'Wikipedia: medicine' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'wikivoyage'; Prefix = 'wikivoyage_en_all_nopic'; Name = 'Wikivoyage: travel guide, no pictures' }
  @{ Lang = 'en'; Tier = 'Standard'; Dir = 'other'; Prefix = 'mdwiki_en_all_maxi'; Name = 'MDWiki: medical encyclopedia' }
  @{ Lang = 'en'; Tier = 'Standard'; Dir = 'other'; Prefix = 'energypedia_en_all_maxi'; Name = 'Energypedia: solar, power, cooking fuel' }
  @{ Lang = 'en'; Tier = 'Standard'; Dir = 'ifixit'; Prefix = 'ifixit_en_all'; Name = 'iFixit: repair guides' }
  @{ Lang = 'en'; Tier = 'Standard'; Dir = 'wikipedia'; Prefix = 'wikipedia_en_all_mini'; NotIn = 'Full'; Name = 'Wikipedia: every article, intro only' }
  @{ Lang = 'en'; Tier = 'Full'; Dir = 'wikipedia'; Prefix = 'wikipedia_en_all_maxi'; Name = 'Wikipedia: complete, with pictures' }
  @{ Lang = 'en'; Tier = 'Lite'; Dir = 'gutenberg'; Prefix = 'gutenberg_en_all'; Opt = $true; Name = 'Project Gutenberg: 70,000 books' }

  @{ Lang = 'pt'; Tier = 'Lite'; Dir = 'wikipedia'; Prefix = 'wikipedia_pt_medicine_maxi'; Name = 'Wikipédia: medicina' }
  @{ Lang = 'pt'; Tier = 'Lite'; Dir = 'wikibooks'; Prefix = 'wikibooks_pt_all_maxi'; Name = 'Wikilivros: livros e manuais' }
  @{ Lang = 'pt'; Tier = 'Lite'; Dir = 'wikivoyage'; Prefix = 'wikivoyage_pt_all_nopic'; Name = 'Wikiviagem: guia de viagem, sem fotos' }
  @{ Lang = 'pt'; Tier = 'Lite'; Dir = 'wikipedia'; Prefix = 'wikipedia_pt_all_mini'; NotIn = 'Standard,Full'; Name = 'Wikipédia: todos os artigos, só a introdução' }
  @{ Lang = 'pt'; Tier = 'Standard'; Dir = 'wikipedia'; Prefix = 'wikipedia_pt_all_nopic'; NotIn = 'Full'; Name = 'Wikipédia: completa, sem fotos' }
  @{ Lang = 'pt'; Tier = 'Standard'; Dir = 'wiktionary'; Prefix = 'wiktionary_pt_all_nopic'; Name = 'Wikcionário: dicionário' }
  @{ Lang = 'pt'; Tier = 'Standard'; Dir = 'wikiversity'; Prefix = 'wikiversity_pt_all_nopic'; Name = 'Wikiversidade: cursos' }
  @{ Lang = 'pt'; Tier = 'Standard'; Dir = 'gutenberg'; Prefix = 'gutenberg_pt_all'; Name = 'Projeto Gutenberg: livros em português' }
  @{ Lang = 'pt'; Tier = 'Full'; Dir = 'wikipedia'; Prefix = 'wikipedia_pt_all_maxi'; Name = 'Wikipédia: completa, com fotos' }
)
# Taken out of the kit. Verify / repair and updates remove these from drives that already have them.
$Retired = [ordered]@{
  'survivors_en_all_maxi' = 'the Vampire Survivors video-game wiki, added by mistake (not survival content)'
}
function Get-RetiredFiles {
  foreach ($p in $Retired.Keys) {
    Get-ChildItem (Join-Path $Target 'library') -Filter "$($p)_*.zim" -ErrorAction SilentlyContinue | ForEach-Object { @{ File = $_; Why = $Retired[$p] } }
  }
}
$LangList = @($Languages.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().ToLower() -replace '^pt-br$', 'pt' })
foreach ($l in $LangList) { if ($l -notin 'en', 'pt') { throw "Unknown language '$l' (use en, pt)" } }

# Map areas: min_lon,min_lat,max_lon,max_lat
$MapPresets = [ordered]@{
  'brazil'            = '-74.0,-33.8,-34.7,5.3'
  'portugal'          = '-9.6,36.9,-6.1,42.2'
  'usa'               = '-125.0,24.4,-66.9,49.4'   # lower 48 states
  'alaska'            = '-179.2,51.2,-129.9,71.5'
  'hawaii'            = '-160.6,18.8,-154.7,22.3'
  'canada'            = '-141.1,41.6,-52.5,83.2'
  'canada-south'      = '-139.1,41.6,-52.5,60.0'   # south of 60N: every province, ~2/3 the size
  'rio-grande-do-sul' = '-57.7,-33.8,-49.6,-27.0'
  'santa-catarina'    = '-53.9,-29.4,-48.3,-25.9'
  'parana'            = '-54.7,-26.8,-48.0,-22.5'
  'sao-paulo'         = '-53.2,-25.4,-44.1,-19.7'
  'rio-de-janeiro'    = '-44.9,-23.4,-40.9,-20.7'
  'minas-gerais'      = '-51.1,-23.0,-39.8,-14.2'
  'bahia'             = '-46.7,-18.4,-37.3,-8.5'
  'pernambuco'        = '-41.4,-9.5,-34.8,-7.2'
}
# USA, Canada and Alaska are cut along the border instead of as rectangles: their rectangles share
# a 7 GB strip (northern US / southern Canada) and Alaska's reaches into Yukon and BC. Both border
# lines are drawn with Canada on their left; each country's outline reaches 8 km past the line
# (sideways, whatever way the line runs), so there is never a gap and border towns are on both maps.
$UsCanadaBorder = '-126.0,48.45 -124.7,48.49 -123.4,48.27 -123.2,48.42 -123.25,48.68 -123.0,48.78 -123.32,49.0 -95.15,49.0 -95.15,49.38 ' +
  '-94.82,49.32 -94.65,48.72 -93.8,48.52 -93.0,48.62 -92.4,48.25 -91.5,48.08 -90.8,48.2 -89.6,48.0 -89.3,48.18 -88.6,48.32 ' +
  '-87.0,47.9 -86.0,47.35 -85.0,46.95 -84.8,46.9 -84.5,46.5 -84.1,46.3 -83.6,46.05 -83.0,45.5 -82.5,45.2 -82.2,44.6 -82.1,43.9 ' +
  '-82.42,42.98 -82.52,42.62 -82.75,42.45 -82.95,42.34 -83.07,42.3 -83.1,42.26 -83.12,42.15 -83.13,42.05 -82.68,41.68 -82.4,41.68 -81.6,41.95 -80.5,42.3 -79.8,42.5 ' +
  '-79.0,42.75 -78.92,42.9 -79.03,43.1 -79.06,43.27 -79.1,43.4 -78.0,43.6 -77.0,43.6 -76.45,44.05 -76.2,44.2 -75.8,44.4 ' +
  '-75.3,44.8 -74.75,45.0 -71.5,45.01 -71.08,45.3 -70.83,45.4 -70.4,45.75 -70.25,46.1 -70.05,46.4 -69.98,46.7 -69.23,47.45 ' +
  '-68.3,47.35 -67.79,47.07 -67.78,45.95 -67.43,45.6 -67.2,45.18 -66.98,44.9 -66.9,44.6 -66.6,44.2 -66.5,40.5'   # west to east
$AlaskaBorder = '-141.0,83.2 -141.0,60.3 -139.07,60.35 -138.0,59.75 -137.5,59.2 -136.6,59.55 -135.5,59.8 -135.0,59.55 ' +
  '-134.0,58.9 -133.4,58.4 -132.2,57.4 -131.2,56.6 -130.1,56.1 -130.0,55.3 -130.6,54.7 -133.6,54.3'   # north to south
# "lon,lat lon,lat ..." moved sideways by $km: positive = to the left of the direction the line is drawn in
function Offset-Points([string]$points, [double]$km) {
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $p = @($points.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { , ([double[]]($_.Split(',') | ForEach-Object { [double]::Parse($_, $inv) })) })
  $kx = { param($lat) 111.32 * [math]::Cos($lat * [math]::PI / 180) }   # km per degree of longitude
  for ($i = 0; $i -lt $p.Count; $i++) {
    # average of the left-hand normals of the segments before and after this point
    $nx = 0.0; $ny = 0.0
    foreach ($s in @(@(($i - 1), $i), @($i, ($i + 1)))) {
      if ($s[0] -lt 0 -or $s[1] -ge $p.Count) { continue }
      $a = $p[$s[0]]; $b = $p[$s[1]]
      $dx = ($b[0] - $a[0]) * (& $kx $a[1]); $dy = ($b[1] - $a[1]) * 110.57
      $len = [math]::Sqrt($dx * $dx + $dy * $dy); if ($len -eq 0) { continue }
      $nx += -$dy / $len; $ny += $dx / $len
    }
    $n = [math]::Sqrt($nx * $nx + $ny * $ny); if ($n -eq 0) { $n = 1 }
    $x = $p[$i][0] + $nx / $n * $km / (& $kx $p[$i][1]); $y = $p[$i][1] + $ny / $n * $km / 110.57
    [string]::Format($inv, '{0},{1}', [math]::Round($x, 3), [math]::Round($y, 3))
  }
}
function Reverse-Points($points) { $a = @($points); [array]::Reverse($a); $a }
$AlaskaSouthOf60 = ($AlaskaBorder.Split(' ') | Select-Object -Skip 3) -join ' '   # from where the border drops below 60N
$Margin = 8   # km past the border, on both sides
$MapRegions = @{   # outline of each country map, as lon,lat points (Canada is left of both border lines)
  'usa'          = @(Offset-Points $UsCanadaBorder $Margin) + '-66.0,24.3', '-125.5,24.3'
  'canada'       = @(Offset-Points $UsCanadaBorder (-$Margin)) + '-52.5,41.6', '-52.5,83.2' + @(Offset-Points $AlaskaBorder (-$Margin)) + '-136.0,54.0', '-136.0,48.35'
  'canada-south' = @(Offset-Points $UsCanadaBorder (-$Margin)) + '-52.5,41.6', '-52.5,60.0', '-138.55,60.0' + @(Offset-Points $AlaskaSouthOf60 (-$Margin)) + '-136.0,54.0', '-136.0,48.35'
  'alaska'       = @('-179.2,51.0') + @(Reverse-Points (Offset-Points ($AlaskaBorder -replace '^-141\.0,83\.2', '-141.0,71.6') $Margin)) + '-179.2,71.7'
}

# Items that contain or replace others: a kit never gets both. The builder skips the smaller one,
# and the builder window greys it out while the bigger one is ticked (and the other way round).
$Contains = [ordered]@{
  'canada'                 = 'canada-south'
  'brazil'                 = 'rio-grande-do-sul', 'santa-catarina', 'parana', 'sao-paulo', 'rio-de-janeiro', 'minas-gerais', 'bahia', 'pernambuco'
  'wikipedia_en_all_maxi'  = 'wikipedia_en_all_mini', 'wikipedia_en_medicine_maxi'
  'wikipedia_pt_all_maxi'  = 'wikipedia_pt_all_nopic', 'wikipedia_pt_all_mini', 'wikipedia_pt_medicine_maxi'
  'wikipedia_pt_all_nopic' = 'wikipedia_pt_all_mini'
}
# the chosen item that already includes $id, if any
function Get-Container($id, $chosen) { foreach ($k in $Contains.Keys) { if ($chosen -contains $k -and @($Contains[$k]) -contains $id) { return $k } } }

$MapLabels = @{   # names shown in the builder window; the rest are title-cased
  'usa' = 'USA (lower 48 states)'; 'canada-south' = 'Canada, south of 60°N (where most people live)'
  'rio-grande-do-sul' = 'Rio Grande do Sul'; 'parana' = 'Paraná'; 'sao-paulo' = 'São Paulo'; 'rio-de-janeiro' = 'Rio de Janeiro'
}
if ($Update -and $Target) {
  # everything already on the kit, in its newest edition (plus any -Items, e.g. broken ones found by -Verify)
  $ItemSet = @($ItemSet) + @($Models | Where-Object { Test-Path (Join-Path $Target "models\$($_.File)") } | ForEach-Object { $_.Id })
  $ItemSet += @($Zims | Where-Object { Test-Path (Join-Path $Target "library\$($_.Prefix)_*.zim") } | ForEach-Object { $_.Prefix })
  $ItemSet += @($MapPresets.Keys | Where-Object { Test-Path (Join-Path $Target "portal\maps\$_.pmtiles") })
  if (Test-Path (Join-Path $Target 'portal\survival-data\index.html')) { $ItemSet += 'survival-data' }
  if (Test-Path (Join-Path $Target 'apps\android')) { $ItemSet += 'apps' }
  if (Test-Path (Join-Path $Target 'models\whisper')) { $ItemSet += 'voice' }
  if (-not (Test-Path (Join-Path $Target 'START-WINDOWS.bat'))) { throw "No Survival Station kit in $Target to update. Build it first." }
  $ItemSet += 'none'   # never empty, so only these are fetched
}
if ($ItemSet) { $Map = ($ItemSet | Where-Object { $MapPresets.Contains($_) }) -join ',' }
$MapList = @()
foreach ($m in ($Map.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().ToLower() })) {
  if (-not $MapPresets.Contains($m)) { throw "Unknown map '$m'. Use one of: $($MapPresets.Keys -join ', '), or -MapBbox" }
  $MapList += @{ Name = $m; Bbox = $MapPresets[$m]; Region = $MapRegions[$m]; MaxZoom = $MapMaxZoom }
}
if ($MapBbox) { $MapList += @{ Name = ($MapName.ToLower() -replace '[^a-z0-9-]', '-'); Bbox = $MapBbox; MaxZoom = $MapMaxZoom } }
$MapList = @(@{ Name = 'world'; Bbox = ''; MaxZoom = 7 }) + $MapList   # ~190 MB overview of the whole planet

$Viewer = @{   # map viewer libraries, pinned
  'maplibre-gl.js'  = 'https://cdn.jsdelivr.net/npm/maplibre-gl@5.24.0/dist/maplibre-gl.js'
  'maplibre-gl.css' = 'https://cdn.jsdelivr.net/npm/maplibre-gl@5.24.0/dist/maplibre-gl.css'
  'pmtiles.js'      = 'https://cdn.jsdelivr.net/npm/pmtiles@4.5.0/dist/pmtiles.js'
  'basemaps.js'     = 'https://cdn.jsdelivr.net/npm/@protomaps/basemaps@5.7.2/dist/basemaps.js'
  'qrcode.js'       = 'https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.js'   # QR code of the kit's address for phones
}

# llama.cpp asset suffix -> engine folder on the drive
$Engines = [ordered]@{
  'bin-win-cpu-x64.zip'       = 'win'
  'bin-macos-arm64.tar.gz'    = 'mac-arm64'
  'bin-macos-x64.tar.gz'      = 'mac-x64'
  'bin-ubuntu-x64.tar.gz'     = 'linux-x64'
  'bin-ubuntu-arm64.tar.gz'   = 'linux-arm64'   # Raspberry Pi 5 etc.
}
$KiwixBuilds = [ordered]@{
  'win-x86_64'   = @{ Folder = 'win'; Ext = 'zip' }
  'macos-arm64'  = @{ Folder = 'mac-arm64'; Ext = 'tar.gz' }
  'macos-x86_64' = @{ Folder = 'mac-x64'; Ext = 'tar.gz' }
  'linux-x86_64' = @{ Folder = 'linux-x64'; Ext = 'tar.gz' }
  'linux-aarch64' = @{ Folder = 'linux-arm64'; Ext = 'tar.gz' }
}

# ---------------------------------------------------------------- helpers

$TierRank = @{ Lite = 1; Standard = 2; Full = 3 }
function In-Tier($item) {
  $TierRank[$item.Tier] -le $TierRank[$Tier] -and (@("$($item.NotIn)".Split(',')) -notcontains $Tier) -and
    (-not $item.Lang -or $LangList -contains $item.Lang) -and (-not $item.Opt -or $Gutenberg)
}
# with -Items, exactly the listed ids; otherwise the tier and languages decide
function Wanted($item, $id) { if ($ItemSet) { $ItemSet -contains $id } else { In-Tier $item } }
# Survival-Data only when asked for (ticked, or already on the kit): its repository states no licence and it
# includes commercial books, so the user decides (see THIRD-PARTY-NOTICES.md)
$WantSD = $ItemSet -contains 'survival-data'
$WantApps = -not $ItemSet -or $ItemSet -contains 'apps'
$WantVoice = -not $ItemSet -or $ItemSet -contains 'voice'
# Voice: whisper.cpp's server turns speech into text for the chat (Windows and Linux builds; none for Mac).
# Multilingual "small" model, 5-bit: about 4 seconds for a short question on a laptop CPU.
$WhisperModel = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin'
$WhisperModelFile = 'models\whisper\ggml-small-q5_1.bin'
$WhisperBuilds = [ordered]@{ 'whisper-bin-x64.zip' = 'win'; 'whisper-bin-ubuntu-x64.tar.gz' = 'linux-x64'; 'whisper-bin-ubuntu-arm64.tar.gz' = 'linux-arm64' }
# Caddy gives the kit a secure address (https on 8443) so phones may use the microphone; same systems as whisper
$CaddyBuilds = [ordered]@{ 'windows_amd64.zip' = 'win'; 'linux_amd64.tar.gz' = 'linux-x64'; 'linux_arm64.tar.gz' = 'linux-arm64' }
function Test-Voice {   # the speech model, and every system's speech server and Caddy, are on the kit
  (Test-Path (Join-Path $Target $WhisperModelFile)) -and
    -not @($WhisperBuilds.Values | Where-Object { -not (Get-ChildItem (Join-Path $Target "tools\$_\whisper") -Filter 'whisper-server*' -ErrorAction SilentlyContinue) }) -and
    -not @($CaddyBuilds.Values | Where-Object { -not (Get-ChildItem (Join-Path $Target "tools\$_\caddy") -Filter 'caddy*' -ErrorAction SilentlyContinue) })
}
function Install-Caddy {
  $missing = @($CaddyBuilds.Keys | Where-Object { -not (Get-ChildItem (Join-Path $Target "tools\$($CaddyBuilds[$_])\caddy") -Filter 'caddy*' -ErrorAction SilentlyContinue) })
  if (-not $missing) { Write-Host '   ok (already have the secure server)'; return }
  $rel = Invoke-RestMethod 'https://api.github.com/repos/caddyserver/caddy/releases/latest'
  foreach ($suffix in $missing) {
    $asset = $rel.assets | Where-Object { $_.name -like "caddy_*_$suffix" } | Select-Object -First 1
    if (-not $asset) { Write-Host "   (no Caddy $suffix in $($rel.tag_name))" -ForegroundColor Yellow; continue }
    $arch = Join-Path $Tmp $asset.name
    Download $asset.browser_download_url $arch
    $x = Join-Path $Tmp "caddy-$($CaddyBuilds[$suffix])"
    if (Test-Path $x) { Remove-Item -Recurse -Force $x }
    Expand-Any $arch $x
    $exe = Get-ChildItem $x -Recurse -File | Where-Object { $_.Name -in 'caddy.exe', 'caddy' } | Select-Object -First 1
    $dst = Join-Path $Target "tools\$($CaddyBuilds[$suffix])\caddy"
    New-Item -ItemType Directory -Force $dst | Out-Null
    if ($exe) { Copy-Item $exe.FullName $dst -Force }
    Remove-Item -Recurse -Force $x, $arch
  }
  Set-Content (Join-Path $Target 'tools\caddy-VERSION') $rel.tag_name
}
function Install-Voice {
  Download $WhisperModel (Join-Path $Target $WhisperModelFile)
  Install-Caddy
  $missing = @($WhisperBuilds.Keys | Where-Object { -not (Get-ChildItem (Join-Path $Target "tools\$($WhisperBuilds[$_])\whisper") -Filter 'whisper-server*' -ErrorAction SilentlyContinue) })
  if (-not $missing) { Write-Host '   ok (already have the voice programs)'; return }
  # the tagged releases (v1.9.x) carry no files: the ready-made programs are on the numbered builds
  $rel = Invoke-RestMethod 'https://api.github.com/repos/ggml-org/whisper.cpp/releases?per_page=15' |
    Where-Object { $_.assets.name -contains 'whisper-bin-x64.zip' } | Select-Object -First 1
  if (-not $rel) { throw 'No whisper.cpp build with ready-made programs found on GitHub' }
  foreach ($name in $missing) {
    $asset = $rel.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $asset) { Write-Host "   (no $name in whisper.cpp $($rel.tag_name); voice won't work on that system)" -ForegroundColor Yellow; continue }
    $arch = Join-Path $Tmp $name
    Download $asset.browser_download_url $arch
    $x = Join-Path $Tmp "whisper-$($WhisperBuilds[$name])"
    if (Test-Path $x) { Remove-Item -Recurse -Force $x }
    Expand-Any $arch $x
    $server = Get-ChildItem $x -Recurse -File | Where-Object { $_.Name -in 'whisper-server.exe', 'whisper-server' } | Select-Object -First 1
    if (-not $server) { Write-Host "   (no whisper-server in $name)" -ForegroundColor Yellow; continue }
    $dst = Join-Path $Target "tools\$($WhisperBuilds[$name])\whisper"
    if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
    New-Item -ItemType Directory -Force $dst | Out-Null
    # the server and the libraries beside it, not the ~40 other example programs
    Get-ChildItem $server.DirectoryName -File | Where-Object { $_.Name -eq $server.Name -or $_.Name -match '\.(dll|so)(\.[\d.]+)?$|\.dylib$' } |
      Copy-Item -Destination $dst
    Remove-Item -Recurse -Force $x, $arch
  }
  Set-Content (Join-Path $Target 'tools\whisper-VERSION') $rel.tag_name
}
$BaseSize = 800MB   # always installed: AI and library programs for 5 systems, map viewer, world map

function Norm-Path($p) { $p.TrimEnd('\').ToLower() }

# The app itself: start files, portal pages, launchers and this builder. MAKE-USB.bat and COPY-KIT.bat
# go on the kit too, so it can update itself and be copied without the project folder.
# (LICENSE and THIRD-PARTY-NOTICES.md go on every kit: a shared kit carries the licences of what is on it)
$AppRootFiles = 'START-WINDOWS.bat', 'START-MAC.command', 'START-LINUX.sh', 'MAKE-USB.bat', 'COPY-KIT.bat', 'PRIVATE-DOCS.bat', 'README.md', 'LEIA-ME.md', 'CHANGELOG.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md'
function Get-AppFiles {   # relative paths of every app file in the project (not the drive's data folders)
  foreach ($f in $AppRootFiles) { if (Test-Path (Join-Path $Root $f)) { $f } }
  foreach ($d in 'portal', 'launch', 'setup') {
    Get-ChildItem (Join-Path $Root $d) -Recurse -File | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\') } |
      Where-Object { $_ -notmatch '^portal\\(maps|vendor|survival-data)\\' }
  }
}
# Survival-Data's index.html hides its lists in CSS, but its click handler reads the inline style,
# so the first click on a heading hid an already hidden list and nothing seemed to happen
function Repair-SurvivalDataPage {
  $page = Join-Path $Target 'portal\survival-data\index.html'
  if (-not (Test-Path $page)) { return }
  $html = [IO.File]::ReadAllText($page)
  $fixed = $html.Replace('ul.style.display === "none" ?', 'getComputedStyle(ul).display === "none" ?')
  if ($fixed -ne $html) { [IO.File]::WriteAllText($page, $fixed, (New-Object Text.UTF8Encoding $true)) }
}
# ---------------------------------------------------------------- search inside the Survival-Data PDFs
# The portal's search page can't read PDFs, so the builder extracts their text once (Poppler's pdftotext)
# into portal\survival-data\search-index\:
#   docs.json      [{f: file, t: title, s: section, o: [byte offset where each page starts, ..., end]}]
#   text\<n>.txt   the text of PDF n, one page per line (the page fetches just one page with a Range request)
#   w\<ab>.json    word -> [doc, page, doc, page, ...] for every word starting with "ab", accents and case folded
# Scanned PDFs have no text and are left out. Raise $PdfIndexVersion when the format changes.
$PdfIndexVersion = '1'
if (-not ('PdfIndexBuilder' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public class PdfIndexBuilder {
  static readonly HashSet<string> Stop = new HashSet<string>(
    ("the and for are but not you all any can had her was one our out has have this that with from they will would there their what about " +
     "which when your into than then them these some could other more also only its may been were his him she who how should each such those " +
     "very most must over same both just where while upon").Split(' '));
  readonly Dictionary<string, List<int>> post = new Dictionary<string, List<int>>();
  static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);

  static string Fold(string s) {
    string d = s.ToLowerInvariant().Normalize(NormalizationForm.FormD);
    var sb = new StringBuilder(d.Length);
    foreach (char c in d) if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
    return sb.ToString();
  }

  static string ShardKey(string token) {   // must match shardKey() in portal/search.html
    var sb = new StringBuilder(2);
    for (int i = 0; i < 2 && i < token.Length; i++) { char c = token[i]; sb.Append((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ? c : '_'); }
    return sb.ToString();
  }

  // Writes the PDF's pages (whitespace collapsed, one page per line) to textPath and indexes their words.
  // Returns the byte offset where each page starts plus the end, or null when there is no text (a scan).
  public long[] AddDoc(int doc, string[] pages, string textPath) {
    int n = pages.Length;
    if (n > 1 && pages[n - 1].Trim().Length == 0) n--;   // pdftotext ends with a page break
    var clean = new string[n];
    int letters = 0;
    for (int p = 0; p < n; p++) { clean[p] = CollapseSpace(pages[p]); letters += clean[p].Length; }
    if (letters < 200) return null;
    var offs = new long[n + 1];
    long at = 0;
    using (var w = new StreamWriter(textPath, false, Utf8)) {
      for (int p = 0; p < n; p++) {
        offs[p] = at;
        string line = clean[p] + "\n";
        w.Write(line); at += Utf8.GetByteCount(line);
        var seen = new HashSet<string>();
        foreach (string tok in Tokens(Fold(clean[p]))) {
          if (!seen.Add(tok)) continue;
          List<int> list;
          if (!post.TryGetValue(tok, out list)) { list = new List<int>(); post[tok] = list; }
          list.Add(doc); list.Add(p + 1);
        }
      }
    }
    offs[n] = at;
    return offs;
  }

  static string CollapseSpace(string s) {
    var sb = new StringBuilder(s.Length); bool sp = false;
    foreach (char c in s) {
      if (char.IsWhiteSpace(c) || char.IsControl(c)) { sp = sb.Length > 0; continue; }
      if (sp) { sb.Append(' '); sp = false; }
      sb.Append(c);
    }
    return sb.ToString();
  }

  static IEnumerable<string> Tokens(string folded) {
    int i = 0, len = folded.Length;
    while (i < len) {
      while (i < len && !char.IsLetterOrDigit(folded[i])) i++;
      int s = i;
      while (i < len && char.IsLetterOrDigit(folded[i])) i++;
      int l = i - s;
      if (l >= 3 && l <= 30) { string t = folded.Substring(s, l); if (!Stop.Contains(t)) yield return t; }
    }
  }

  public int WriteShards(string dir) {
    Directory.CreateDirectory(dir);
    var shards = new Dictionary<string, List<string>>();
    foreach (var kv in post) {
      string key = ShardKey(kv.Key);
      List<string> l;
      if (!shards.TryGetValue(key, out l)) { l = new List<string>(); shards[key] = l; }
      l.Add(kv.Key);
    }
    foreach (var sh in shards) {
      var sb = new StringBuilder("{");
      bool first = true;
      foreach (string tok in sh.Value) {
        if (!first) sb.Append(','); first = false;
        sb.Append('"').Append(tok).Append("\":[").Append(string.Join(",", post[tok])).Append(']');
      }
      sb.Append('}');
      File.WriteAllText(Path.Combine(dir, sh.Key + ".json"), sb.ToString(), Utf8);
    }
    return shards.Count;
  }
}
'@
}

# pdftotext from Poppler for Windows (~42 MB download), kept in %TEMP% for the next build
function Get-PdfTextTool {
  $dir = Join-Path $env:TEMP 'survival-station-tools\poppler'
  # (Test-Path first: on a missing folder, -Recurse would search the whole folder above it)
  $exe = if (Test-Path $dir) { Get-ChildItem $dir -Recurse -Filter pdftotext.exe -ErrorAction SilentlyContinue | Select-Object -First 1 }
  if ($exe) { return $exe.FullName }
  $rel = Invoke-RestMethod 'https://api.github.com/repos/oschwartz10612/poppler-windows/releases/latest'
  $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
  $zip = Join-Path $env:TEMP "survival-station-tools\$($asset.name)"
  New-Item -ItemType Directory -Force (Split-Path $zip) | Out-Null
  Write-Host ("   downloading the PDF text tool (Poppler, {0:N0} MB)" -f ($asset.size / 1MB))
  & curl.exe -sSL --fail --retry 3 -o $zip $asset.browser_download_url
  if ($LASTEXITCODE -ne 0) { throw "Could not download the PDF text tool (curl code $LASTEXITCODE)" }
  Expand-Any $zip $dir
  Remove-Item $zip -Force
  (Get-ChildItem $dir -Recurse -Filter pdftotext.exe | Select-Object -First 1).FullName
}

function Test-PdfIndex {   # $true when the kit's Survival-Data has a finished index of the current format
  $v = Join-Path $Target 'portal\survival-data\search-index\version.txt'
  (Test-Path $v) -and "$(Get-Content $v -ErrorAction SilentlyContinue)".Trim() -eq $PdfIndexVersion
}

function Build-PdfIndex {
  $sd = Join-Path $Target 'portal\survival-data'
  if (-not (Test-Path (Join-Path $sd 'index.html'))) { return }
  if (Test-PdfIndex) { Write-Host '   ok (already built)'; return }
  $exe = Get-PdfTextTool
  # titles as Survival-Data's own page shows them
  $titles = @{}
  foreach ($m in [regex]::Matches([IO.File]::ReadAllText((Join-Path $sd 'index.html')), '<a href="([^"]+\.pdf)"[^>]*>([^<]+)</a>')) {
    $titles[[Net.WebUtility]::HtmlDecode([uri]::UnescapeDataString($m.Groups[1].Value))] = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value).Trim()
  }
  # built on this computer's disk, then copied over in one go (a half-built index never lands on the kit)
  $work = Join-Path $env:TEMP 'survival-station-pdfindex'
  if (Test-Path $work) { Remove-Item -Recurse -Force $work }
  New-Item -ItemType Directory -Force (Join-Path $work 'text') | Out-Null
  $b = New-Object PdfIndexBuilder
  $pdfs = @(Get-ChildItem $sd -Recurse -Filter *.pdf | Where-Object { $_.FullName -notlike "*\search-index\*" } | Sort-Object FullName)
  $docs = New-Object Collections.ArrayList
  $scans = 0; $i = 0
  $tmp = Join-Path $work 'page.txt'
  foreach ($f in $pdfs) {
    $i++
    if ($i % 25 -eq 0) { Write-Host ("   reading the PDFs: {0} of {1}" -f $i, $pdfs.Count) }
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    $ErrorActionPreference = 'Continue'   # a damaged PDF writes to stderr
    & $exe -enc UTF-8 -q $f.FullName $tmp 2>$null
    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path $tmp)) { $scans++; continue }
    $n = $docs.Count
    $offs = $b.AddDoc($n, ([IO.File]::ReadAllText($tmp) -split "`f"), (Join-Path $work "text\$n.txt"))
    if (-not $offs) { $scans++; Remove-Item (Join-Path $work "text\$n.txt") -Force -ErrorAction SilentlyContinue; continue }
    $rel = $f.FullName.Substring($sd.Length + 1).Replace('\', '/')
    $title = if ($titles.ContainsKey($rel)) { $titles[$rel] } else { $f.BaseName -replace '[-_.]+', ' ' }
    [void]$docs.Add([ordered]@{ f = $rel; t = $title; s = ($f.Directory.Name -replace '-', ' '); o = $offs })
  }
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  $shards = $b.WriteShards((Join-Path $work 'w'))
  [IO.File]::WriteAllText((Join-Path $work 'docs.json'), (ConvertTo-Json -InputObject @($docs) -Depth 4 -Compress), (New-Object Text.UTF8Encoding $false))
  $mb = (Get-ChildItem $work -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
  Write-Host ("   {0} PDFs indexed, {1} scanned ones have no text; copying the index to the drive ({2:N0} MB)..." -f $docs.Count, $scans, $mb)
  $idx = Join-Path $sd 'search-index'
  if (Test-Path $idx) { Remove-Item -Recurse -Force $idx }
  & robocopy.exe $work $idx /E /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "Copying the PDF search index to the drive failed (robocopy code $LASTEXITCODE)" }
  $global:LASTEXITCODE = 0   # robocopy's 1 means "files copied", not an error
  Set-Content (Join-Path $idx 'version.txt') $PdfIndexVersion   # last: marks the index finished
  Remove-Item -Recurse -Force $work
  Write-Host '   done'
}

# ---------------------------------------------------------------- place names for the map's search box
# GeoNames (free, CC BY 4.0): every town of 500+ people worldwide, plus, for each country with a street map
# on the kit, its towns, neighbourhoods, hospitals, airports, mountains, lakes and parks inside the maps.
# Written to portal\maps\places\: <ab>.json = places with a word starting "ab", biggest first;
# type-hospital.json etc. = every place of that type, for "nearest hospital". version.txt names the maps
# it was made for, so adding a map rebuilds it. Raise $PlacesVersion when the format changes.
$PlacesVersion = '1'
$MapCountries = @{ 'brazil' = 'BR'; 'portugal' = 'PT'; 'usa' = 'US'; 'alaska' = 'US'; 'hawaii' = 'US'; 'canada' = 'CA'; 'canada-south' = 'CA'
  'rio-grande-do-sul' = 'BR'; 'santa-catarina' = 'BR'; 'parana' = 'BR'; 'sao-paulo' = 'BR'; 'rio-de-janeiro' = 'BR'; 'minas-gerais' = 'BR'; 'bahia' = 'BR'; 'pernambuco' = 'BR' }
if (-not ('PlacesBuilder' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

public class PlacesBuilder {
  // kinds kept from the country files (the world list is all towns)
  static readonly HashSet<string> Kinds = new HashSet<string>(
    "PPL PPLA PPLA2 PPLA3 PPLA4 PPLA5 PPLC PPLCD PPLF PPLG PPLL PPLR PPLS PPLX HSP HSPC HSPD AIRP AIRF AIRH FIRE PP MT PK LK PRK".Split(' '));
  // kinds people look for by type ("hospital"): also written to one file per type, to list the nearest ones
  static readonly Dictionary<string, string> Types = new Dictionary<string, string> {
    { "HSP", "hospital" }, { "HSPC", "hospital" }, { "HSPD", "hospital" },
    { "AIRP", "airport" }, { "AIRF", "airport" }, { "AIRH", "airport" }, { "FIRE", "fire" }, { "PP", "police" } };
  // a word in more names than this ("lake", "saint", "north") isn't a file of its own: it would be huge.
  // Such names are still found by their other words ("Lake Tahoe" by "tahoe").
  const int CommonWord = 1500;
  class Place { public string Name; public double Lat, Lon; public string Code, Admin, Cc; public long Pop; public List<string> Alt = new List<string>(); }
  readonly Dictionary<string, Place> places = new Dictionary<string, Place>();
  readonly Dictionary<string, string> admin1 = new Dictionary<string, string>();
  static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
  static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

  public void LoadAdmin1(string path) {
    foreach (string line in File.ReadLines(path, Encoding.UTF8)) {
      string[] c = line.Split('\t');
      if (c.Length >= 2) admin1[c[0]] = c[1];
    }
  }

  // A GeoNames file. bboxes: minLon,minLat,maxLon,maxLat, four numbers per box; null = everywhere.
  // filterKinds: keep only the Kinds above (country files list every farm, stream and church).
  public int AddFile(string path, double[] bboxes, bool filterKinds) {
    int added = 0;
    foreach (string line in File.ReadLines(path, Encoding.UTF8)) {
      string[] c = line.Split('\t');
      if (c.Length < 15) continue;
      if (filterKinds && !Kinds.Contains(c[7])) continue;
      double lat = double.Parse(c[4], Inv), lon = double.Parse(c[5], Inv);
      if (bboxes != null) {
        bool inside = false;
        for (int i = 0; i + 3 < bboxes.Length; i += 4)
          if (lon >= bboxes[i] && lat >= bboxes[i + 1] && lon <= bboxes[i + 2] && lat <= bboxes[i + 3]) { inside = true; break; }
        if (!inside) continue;
      }
      if (places.ContainsKey(c[0])) continue;
      long pop; long.TryParse(c[14], out pop);
      string adm; admin1.TryGetValue(c[8] + "." + c[10], out adm);
      var p = new Place { Name = c[1], Lat = lat, Lon = lon, Code = c[7], Admin = adm ?? "", Cc = c[8], Pop = pop };
      // other names (Lisbon / Lisboa) for bigger places only: the list is long and mostly other scripts
      if (pop >= 50000 && c[3].Length > 0)
        foreach (string a in c[3].Split(','))
          if (a.Length > 1 && a.Length <= 40 && IsLatin(a) && a != c[1] && !p.Alt.Contains(a) && p.Alt.Count < 8) p.Alt.Add(a);
      places[c[0]] = p;
      added++;
    }
    return added;
  }

  // countries with at least a tenth of the world list's towns inside the boxes (for a map drawn by hand)
  public static string[] CountriesIn(string worldList, double[] bboxes) {
    var n = new Dictionary<string, int>(); int all = 0;
    foreach (string line in File.ReadLines(worldList, Encoding.UTF8)) {
      string[] c = line.Split('\t');
      if (c.Length < 15) continue;
      double lat = double.Parse(c[4], Inv), lon = double.Parse(c[5], Inv);
      for (int i = 0; i + 3 < bboxes.Length; i += 4)
        if (lon >= bboxes[i] && lat >= bboxes[i + 1] && lon <= bboxes[i + 2] && lat <= bboxes[i + 3]) {
          int k; n.TryGetValue(c[8], out k); n[c[8]] = k + 1; all++; break;
        }
    }
    var r = new List<string>();
    foreach (var kv in n) if (kv.Value * 10 >= all) r.Add(kv.Key);
    return r.ToArray();
  }

  static bool IsLatin(string s) { foreach (char ch in s) if (ch > 0x24F) return false; return true; }

  static string Fold(string s) {
    string d = s.ToLowerInvariant().Normalize(NormalizationForm.FormD);
    var sb = new StringBuilder(d.Length);
    foreach (char c in d) if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
    return sb.ToString();
  }
  static string ShardKey(string w) {   // must match shardKey() in portal/map.html
    var sb = new StringBuilder(2);
    for (int i = 0; i < 2 && i < w.Length; i++) { char c = w[i]; sb.Append((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ? c : '_'); }
    return sb.ToString();
  }
  static IEnumerable<string> Words(string folded) {
    int i = 0, len = folded.Length;
    while (i < len) {
      while (i < len && !char.IsLetterOrDigit(folded[i])) i++;
      int s = i;
      while (i < len && char.IsLetterOrDigit(folded[i])) i++;
      if (i - s >= 2) yield return folded.Substring(s, i - s);
    }
  }
  static string J(string s) {   // JSON string
    var sb = new StringBuilder("\"");
    foreach (char c in s) {
      if (c == '"' || c == '\\') sb.Append('\\').Append(c);
      else if (c < 0x20) sb.Append(' ');
      else sb.Append(c);
    }
    return sb.Append('"').ToString();
  }

  // one file per first two letters of each word of each name:
  // [[name, lat, lon, kind, state, country, population, "other name"], ...], biggest places first
  public int Write(string dir) {
    Directory.CreateDirectory(dir);
    var count = new Dictionary<string, int>();
    foreach (var p in places.Values) {
      var seen = new HashSet<string>();
      foreach (string w in Words(Fold(p.Name))) if (seen.Add(w)) { int n; count.TryGetValue(w, out n); count[w] = n + 1; }
    }
    var shown = new Dictionary<string, Dictionary<Place, string>>();   // shard -> place -> the name it is found by
    var types = new Dictionary<string, List<Place>>();
    foreach (var p in places.Values) {
      string ty;
      if (Types.TryGetValue(p.Code, out ty)) { List<Place> l; if (!types.TryGetValue(ty, out l)) { l = new List<Place>(); types[ty] = l; } l.Add(p); }
      var names = new List<string> { p.Name }; names.AddRange(p.Alt);
      foreach (string n in names) {
        var ws = new List<string>(Words(Fold(n)));
        bool rare = false;
        foreach (string w in ws) { int c; count.TryGetValue(w, out c); if (c <= CommonWord) rare = true; }
        foreach (string w in ws) {
          int c; count.TryGetValue(w, out c);
          if (rare && c > CommonWord) continue;   // found by its rarer words
          string k = ShardKey(w);
          Dictionary<Place, string> m;
          if (!shown.TryGetValue(k, out m)) { m = new Dictionary<Place, string>(); shown[k] = m; }
          if (!m.ContainsKey(p)) m[p] = n == p.Name ? "" : n;
        }
      }
    }
    foreach (var sh in shown) {
      var list = new List<KeyValuePair<Place, string>>(sh.Value);
      list.Sort((a, b) => b.Key.Pop.CompareTo(a.Key.Pop));
      WriteList(Path.Combine(dir, sh.Key + ".json"), list);
    }
    foreach (var ty in types) {
      var list = new List<KeyValuePair<Place, string>>();
      foreach (var p in ty.Value) list.Add(new KeyValuePair<Place, string>(p, ""));
      WriteList(Path.Combine(dir, "type-" + ty.Key + ".json"), list);
    }
    return places.Count;
  }

  static void WriteList(string path, List<KeyValuePair<Place, string>> list) {
    var sb = new StringBuilder("[");
    bool first = true;
    foreach (var kv in list) {
      var p = kv.Key;
      if (!first) sb.Append(','); first = false;
      sb.Append('[').Append(J(p.Name)).Append(',')
        .Append(Math.Round(p.Lat, 5).ToString(Inv)).Append(',').Append(Math.Round(p.Lon, 5).ToString(Inv)).Append(',')
        .Append(J(p.Code)).Append(',').Append(J(p.Admin)).Append(',').Append(J(p.Cc)).Append(',').Append(p.Pop.ToString(Inv));
      if (kv.Value.Length > 0) sb.Append(',').Append(J(kv.Value));
      sb.Append(']');
    }
    sb.Append(']');
    File.WriteAllText(path, sb.ToString(), Utf8);
  }
}
'@
}

function Get-StreetMaps {   # the kit's maps other than the world overview, with their bounds from the file header
  foreach ($f in Get-ChildItem (Join-Path $Target 'portal\maps') -Filter *.pmtiles -File -ErrorAction SilentlyContinue) {
    if ($f.BaseName -eq 'world') { continue }
    $h = Read-Head $f.FullName 127
    if ($h.Length -lt 118 -or [Text.Encoding]::ASCII.GetString($h, 0, 7) -ne 'PMTiles') { continue }
    @{ Name = $f.BaseName; Box = [double[]]@(102, 106, 110, 114 | ForEach-Object { [BitConverter]::ToInt32($h, $_) / 1e7 }) }
  }
}
function Get-PlacesStamp { "$PlacesVersion|" + ((@(Get-StreetMaps | ForEach-Object { $_.Name }) | Sort-Object) -join ',') }
function Test-Places {
  $v = Join-Path $Target 'portal\maps\places\version.txt'
  (Test-Path $v) -and "$(Get-Content $v -ErrorAction SilentlyContinue)".Trim() -eq (Get-PlacesStamp)
}

# a GeoNames file, kept in %TEMP% for 30 days; returns the path of its .txt
function Get-GeoNames($name) {
  $dir = Join-Path $env:TEMP 'survival-station-tools\geonames'
  $txt = Join-Path $dir "$name\$name.txt"
  if ((Test-Path $txt) -and (Get-Item $txt).LastWriteTime -gt (Get-Date).AddDays(-30)) { return $txt }
  New-Item -ItemType Directory -Force $dir | Out-Null
  $zip = Join-Path $dir "$name.zip"
  Write-Host "   downloading place names: $name"
  & curl.exe -sSL --fail --retry 3 -o $zip "https://download.geonames.org/export/dump/$name.zip"
  if ($LASTEXITCODE -ne 0) { throw "Could not download the place names $name.zip (curl code $LASTEXITCODE)" }
  if (Test-Path (Join-Path $dir $name)) { Remove-Item -Recurse -Force (Join-Path $dir $name) }
  Expand-Any $zip (Join-Path $dir $name)   # each in its own folder: every zip has a readme.txt
  Remove-Item $zip -Force
  (Get-Item $txt).LastWriteTime = Get-Date
  $txt
}

function Build-Places {
  if (Test-Places) { Write-Host '   ok (already built for these maps)'; return }
  $dir = Join-Path $env:TEMP 'survival-station-tools\geonames'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $admin = Join-Path $dir 'admin1CodesASCII.txt'
  if (-not (Test-Path $admin) -or (Get-Item $admin).LastWriteTime -lt (Get-Date).AddDays(-30)) {
    & curl.exe -sSL --fail --retry 3 -o $admin 'https://download.geonames.org/export/dump/admin1CodesASCII.txt'
    if ($LASTEXITCODE -ne 0) { throw "Could not download the GeoNames state names (curl code $LASTEXITCODE)" }
  }
  $world = Get-GeoNames 'cities500'
  $b = New-Object PlacesBuilder
  $b.LoadAdmin1($admin)
  [void]$b.AddFile($world, $null, $false)
  $maps = @(Get-StreetMaps)
  if ($maps) {
    $boxes = [double[]]@($maps | ForEach-Object { $_.Box })
    $countries = @($maps | ForEach-Object { if ($MapCountries.Contains($_.Name)) { $MapCountries[$_.Name] } else { [PlacesBuilder]::CountriesIn($world, $_.Box) } }) | Select-Object -Unique
    foreach ($cc in $countries) { [void]$b.AddFile((Get-GeoNames $cc), $boxes, $true) }
  }
  $work = Join-Path $env:TEMP 'survival-station-places'
  if (Test-Path $work) { Remove-Item -Recurse -Force $work }
  $n = $b.Write($work)
  $mb = (Get-ChildItem $work -File | Measure-Object Length -Sum).Sum / 1MB
  Write-Host ("   {0:N0} places; copying them to the drive ({1:N0} MB)..." -f $n, $mb)
  $dst = Join-Path $Target 'portal\maps\places'
  if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
  & robocopy.exe $work $dst /E /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "Copying the place names to the drive failed (robocopy code $LASTEXITCODE)" }
  $global:LASTEXITCODE = 0
  Set-Content (Join-Path $dst 'version.txt') (Get-PlacesStamp)   # last: marks it finished
  Remove-Item -Recurse -Force $work
  Write-Host '   done'
}

function Copy-AppFiles {
  Repair-SurvivalDataPage
  if ((Norm-Path $Root) -eq (Norm-Path $Target)) { Write-Host '   (this builder runs from the kit itself: app files are already in place)'; return }
  foreach ($f in $AppRootFiles) { Copy-Item -Force (Join-Path $Root $f) $Target }
  foreach ($d in 'portal', 'launch', 'setup') { Copy-Item -Recurse -Force (Join-Path $Root $d) $Target }
  # how to load the AI models in a phone app (opens in the iPhone Files app, no computer needed)
  New-Item -ItemType Directory -Force (Join-Path $Target 'models') | Out-Null
  Copy-Item -Force (Join-Path $PSScriptRoot 'PHONE-AI-SETUP.txt') (Join-Path $Target 'models\PHONE-AI-SETUP.txt')
}
function Write-Choices {
  $rows = @(); $ids = @(); $custom = ''
  foreach ($m in $modelList) { $rows += , @('AI model ', 'Modelo IA', $m.Name); $ids += $m.Id }
  foreach ($z in $zimList) { $rows += , @('Library  ', 'Biblioteca', $z.Name); $ids += $z.Prefix }
  foreach ($m in $MapList | Where-Object { $_.Name -ne 'world' }) {
    $rows += , @('Map      ', 'Mapa     ', "$($m.Name) (zoom 0-$($m.MaxZoom))")
    if ($MapPresets.Contains($m.Name)) { $ids += $m.Name } else { $custom = '{0}|{1}|{2}' -f $m.Name, $m.Bbox, [int64]$m.Size }
  }
  if ($WantSD) { $rows += , @('Extra    ', 'Extra    ', 'Survival-Data'); $ids += 'survival-data' }
  if ($WantApps) { $rows += , @('Extra    ', 'Extra    ', 'Android apps / apps Android'); $ids += 'apps' }
  if ($WantVoice) { $rows += , @('Extra    ', 'Extra    ', 'Voice / voz (speech to text)'); $ids += 'voice' }
  $drive = $Target.TrimEnd('\')
  $when = (Get-Date).ToString('yyyy-MM-dd HH:mm')
  $en = ($rows | ForEach-Object { "   $($_[0])  $($_[2])" }) -join "`r`n"
  $pt = ($rows | ForEach-Object { "   $($_[1])  $($_[2])" }) -join "`r`n"
  $text = @"
SURVIVAL STATION - WHAT THIS DRIVE WAS BUILT WITH
(Português abaixo)

Build started: $when   (Survival Station $AppVersion)

If the build stopped (window closed, internet or power cut), nothing is lost.
To finish it later, on a Windows computer with internet:
  1. Double-click MAKE-USB.bat (on this drive, or in the Survival Station folder).
  2. Choose this drive. The items below are ticked again automatically.
  3. Click "Build the drive". Finished files are skipped and half-done
     downloads continue where they stopped.
  4. When it says Done, click "Verify / repair" to check everything.
Text mode: MAKE-USB.bat text, option R. Command line:
  powershell -ExecutionPolicy Bypass -File setup\build-drive.ps1 -Drive "$drive" -Resume

Chosen items ($($rows.Count)):
$en


====================================================================
O QUE FOI ESCOLHIDO PARA ESTE PENDRIVE

Montagem iniciada: $when   (Survival Station $AppVersion)

Se a montagem parou (janela fechada, internet ou energia caiu), nada se perde.
Para terminar depois, num computador Windows com internet:
  1. Clique duas vezes em MAKE-USB.bat (neste pendrive ou na pasta do Survival Station).
  2. Escolha este pendrive. Os itens abaixo voltam marcados sozinhos.
  3. Clique em "Montar o pendrive". Os arquivos prontos são pulados e os
     downloads pela metade continuam de onde pararam.
  4. Quando aparecer Done, clique em "Verificar / reparar" para conferir tudo.
Modo texto: MAKE-USB.bat text, opção R. Linha de comando:
  powershell -ExecutionPolicy Bypass -File setup\build-drive.ps1 -Drive "$drive" -Resume

Itens escolhidos ($($rows.Count)):
$pt


$ChoicesMarker
items=$($ids -join ',')
zoom=$MapMaxZoom
custom=$custom
"@
  [IO.File]::WriteAllText($ChoicesFile, ($text -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding $true))
  Write-Host "   Choices saved: $ChoicesFile (to finish later if this stops)"
}

function Test-Same($file, $size) { $size -gt 0 -and (Test-Path $file) -and (Get-Item $file).Length -eq $size }

function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

# ---------------------------------------------------------------- overall progress
# One bar for the whole build (console, window title and logs\progress.json for the builder window)
$script:prog = @{ Total = 0.0; Done = 0.0; Item = ''; Rate = 0.0; Mark = 0.0; MarkTime = Get-Date; Shown = [datetime]::MinValue }
$ProgressFile = Join-Path $LogDir 'progress.json'

function Fmt-Size([double]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
function Fmt-Speed([double]$b) {   # 740 KB/s, 0.98 MB/s, 12 MB/s
  if ($b -le 0) { '-' } elseif ($b -lt 1MB) { '{0:N0} KB/s' -f ($b / 1KB) } elseif ($b -lt 10MB) { '{0:N2} MB/s' -f ($b / 1MB) } else { '{0:N0} MB/s' -f ($b / 1MB) }
}
function Fmt-Time([double]$s) {
  if ($s -lt 0) { return '?' }
  $t = [TimeSpan]::FromSeconds($s)
  if ($t.TotalDays -ge 1) { '{0}d {1}h' -f [int][math]::Floor($t.TotalDays), $t.Hours } elseif ($t.TotalHours -ge 1) { '{0}h {1:D2}m' -f [int][math]::Floor($t.TotalHours), $t.Minutes } elseif ($t.TotalMinutes -ge 1) { "$($t.Minutes) min" } else { '< 1 min' }
}

function Show-Progress([double]$current = 0, [switch]$Force, [string]$State = 'running') {
  $p = $script:prog
  if ($p.Total -le 0) { return }   # still planning (or only checking sizes)
  $now = Get-Date
  if (-not $Force -and ($now - $p.Shown).TotalMilliseconds -lt 1000) { return }
  $p.Shown = $now
  $done = $p.Done + $current
  $dt = ($now - $p.MarkTime).TotalSeconds
  if ($dt -ge 2) {   # download speed, smoothed so the time left doesn't jump around
    $speed = [math]::Max(0.0, ($done - $p.Mark) / $dt)
    $p.Rate = if ($p.Rate -gt 0) { 0.85 * $p.Rate + 0.15 * $speed } else { $speed }
    $p.Mark = $done; $p.MarkTime = $now
  }
  $pct = if ($p.Total -gt 0) { [math]::Min(99, [int](100 * $done / $p.Total)) } else { 0 }
  if ($State -eq 'done') { $pct = 100 }
  $left = if ($p.Rate -gt 1KB) { [math]::Max(0.0, $p.Total - $done) / $p.Rate } else { -1 }
  $script:overall = '{0}% of the build done: {1} of {2}, about {3} left' -f $pct, (Fmt-Size $done), (Fmt-Size $p.Total), (Fmt-Time $left)
  $script:ov = @{ Pct = $pct; Done = $done; Total = $p.Total; Rate = $p.Rate; Left = $left }   # for the progress table
  # the console shows each file's own live progress (curl, map tool); the overall figure goes in the title
  try { $Host.UI.RawUI.WindowTitle = "$pct% - Survival Station build ($(Fmt-Time $left) left)" } catch { }
  try {
    $json = [ordered]@{ target = $Target; state = $State; percent = $pct; done = [int64]$done; total = [int64]$p.Total
      speed = [int64]$p.Rate; secondsLeft = [int]$left; item = $p.Item; updated = $now.ToString('s'); log = $Log }
    Write-Json $json $ProgressFile
    # a copy on the kit itself, for the portal's "My kit" page
    $onKit = Join-Path $Target 'logs\progress.json'
    if ($onKit -ne $ProgressFile) { New-Item -ItemType Directory -Force (Split-Path $onKit) | Out-Null; Write-Json $json $onKit }
  } catch { }
}

# one line after each finished file: where the whole build stands
function Write-Overall { if ($script:overall) { Write-Host "   >> $script:overall" -ForegroundColor Cyan } }

# ---------------------------------------------------------------- live progress table
# Drawn once per file, then its two rows are rewritten in place every half second:
#   ┌──────────────┬────────────────┬────────────────────────┬──────────────┬─────────────┐
#   │ This file    │ ██░░░░░░░░  4% │ 117.6 MB of 2.5 GB     │ 0.98 MB/s    │ 41 min      │
#   │ Whole build  │ █░░░░░░░░░ 12% │ 17.2 GB of 144.0 GB    │ 0.98 MB/s    │ 1d 12h      │
# Written with [Console] (not Write-Host) so the build log isn't filled with every update. Where there is
# no console to redraw (output redirected, narrow window), a plain line is printed every 15 seconds instead.
$TableCols = 12, 15, 22, 12, 11
function Table-Cell($s, $w) { $s = "$s"; if ($s.Length -gt $w) { $s = $s.Substring(0, $w) }; ' ' + $s.PadRight($w) + ' ' }
function Table-Border($l, $m, $r) { '   ' + $l + (($TableCols | ForEach-Object { '─' * ($_ + 2) }) -join $m) + $r }
function Table-Row($cells) { '   │' + ((0..4 | ForEach-Object { Table-Cell $cells[$_] $TableCols[$_] }) -join '│') + '│' }
function Table-Bar([double]$pct) { $f = [int][math]::Round([math]::Min(100.0, [math]::Max(0.0, $pct)) / 10); ('█' * $f) + ('░' * (10 - $f)) + ('{0,4:0}%' -f $pct) }

function Start-ProgressTable($label) {
  $script:table = @{ Label = $label; Row = -1; Last = [datetime]::MinValue }
  try {
    if ([Console]::IsOutputRedirected -or [Console]::WindowWidth -lt 95) { throw 'no room' }
    $lines = @((Table-Border '┌' '┬' '┐'), (Table-Row @('', 'Done', 'Downloaded', 'Speed', 'Time left')), (Table-Border '├' '┼' '┤'), '', '', (Table-Border '└' '┴' '┘'))
    foreach ($l in $lines) { [Console]::WriteLine($l) }
    $script:table.Row = [Console]::CursorTop - 3   # first data row
  } catch { $script:table.Row = -1 }
}

# $file = @{ Pct; Done; Size; Speed; Left } for the current file or map; the whole build comes from Show-Progress
function Update-ProgressTable($file, [switch]$Force) {
  $t = $script:table
  if (-not $t) { return }
  $o = $script:ov
  $speed = { param($v) Fmt-Speed $v }
  $row1 = Table-Row @($t.Label, (Table-Bar $file.Pct), ('{0} of {1}' -f (Fmt-Size $file.Done), $(if ($file.Size) { Fmt-Size $file.Size } else { '?' })), (& $speed $file.Speed), (Fmt-Time $file.Left))
  $row2 = if ($o) { Table-Row @('Whole build', (Table-Bar $o.Pct), ('{0} of {1}' -f (Fmt-Size $o.Done), (Fmt-Size $o.Total)), (& $speed $o.Rate), (Fmt-Time $o.Left)) } else { Table-Row @('Whole build', '', '', '', '') }
  if ($t.Row -ge 0) {
    try {
      $back = [Console]::CursorTop
      [Console]::SetCursorPosition(0, $t.Row); [Console]::Write($row1)
      [Console]::SetCursorPosition(0, $t.Row + 1); [Console]::Write($row2)
      [Console]::SetCursorPosition(0, [math]::Max($back, $t.Row + 3))
      return
    } catch { $t.Row = -1 }
  }
  if ($Force -or ((Get-Date) - $t.Last).TotalSeconds -ge 15) {   # no console to redraw: a plain line now and then
    $t.Last = Get-Date
    Write-Host ('   {0}: {1:0}% ({2} of {3}), whole build {4}%, about {5} left' -f $t.Label, $file.Pct, (Fmt-Size $file.Done), $(if ($file.Size) { Fmt-Size $file.Size } else { '?' }), $o.Pct, (Fmt-Time $o.Left))
  }
}

# last "NN%" in a file another program is still writing (the map tool's progress)
function Get-LastPercent($file) {
  try {
    $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
    try { [void]$fs.Seek([math]::Max([int64]0, $fs.Length - 4096), 'Begin'); $text = (New-Object IO.StreamReader $fs).ReadToEnd() } finally { $fs.Close() }
    $m = [regex]::Matches($text, '(\d{1,3})%')
    if ($m.Count) { [int]$m[$m.Count - 1].Groups[1].Value } else { 0 }
  } catch { 0 }
}

function Get-RemoteSize($url) {
  try { [int64](Invoke-WebRequest $url -Method Head -UseBasicParsing -MaximumRedirection 10).Headers['Content-Length'] } catch { 0 }
}

# curl.exe ships with Windows 10+; it resumes (-C -) and survives flaky connections far better than Invoke-WebRequest
function Download($url, $dest) {
  $size = Get-RemoteSize $url
  if ((Test-Path $dest) -and $size -gt 0 -and (Get-Item $dest).Length -eq $size) {
    Write-Host "   ok (already have) $(Split-Path $dest -Leaf)"; return
  }
  New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
  $part = "$dest.part"
  $human = if ($size -ge 1GB) { '{0:N2} GB' -f ($size / 1GB) } elseif ($size -gt 0) { '{0:N0} MB' -f [math]::Max(1.0, $size / 1MB) } else { 'size unknown' }
  Write-Host "   downloading $(Split-Path $dest -Leaf) ($human)"
  $script:prog.Item = Split-Path $dest -Leaf
  # on a slow drive, download to this computer's disk and copy the finished file over (see Set-Staging);
  # a half-finished download already on the drive just continues there
  $stage = if ($script:stageFiles -and $size -gt 0 -and -not (Test-Path $part)) { Get-StageDir $size (Split-Path $dest -Leaf) }
  $fetch = if ($stage) { Join-Path $stage ((Split-Path $dest -Leaf) + '.part') } else { $part }
  if (Test-Path $fetch) { $script:prog.Mark += (Get-Item $fetch).Length }   # resumed bytes aren't download speed
  $code = 1
  for ($try = 1; $try -le 5; $try++) {
    # curl runs quietly in the background; the progress table follows the .part file every half second
    # (this file and the whole build), as do the title, the builder window and the My kit page
    $p = Start-Process curl.exe -NoNewWindow -PassThru -ArgumentList @('-L', '--fail', '--retry', '5', '--retry-delay', '5', '-C', '-', '-s', '-S', '-o', "`"$fetch`"", "`"$url`"")
    $null = $p.Handle   # keeps ExitCode readable after the process ends
    Add-ChildProcess $p
    Start-ProgressTable 'This file'
    $last = if (Test-Path $fetch) { (Get-Item $fetch).Length } else { 0 }; $lastTime = Get-Date; $speed = 0.0
    while (-not $p.HasExited) {
      Start-Sleep -Milliseconds 500
      $cur = if (Test-Path $fetch) { (Get-Item $fetch).Length } else { 0 }
      $dt = ((Get-Date) - $lastTime).TotalSeconds
      if ($dt -ge 1) { $now = ($cur - $last) / $dt; $speed = if ($speed -gt 0) { 0.7 * $speed + 0.3 * $now } else { $now }; $last = $cur; $lastTime = Get-Date }
      Show-Progress $cur
      $pct = if ($size -gt 0) { 100.0 * $cur / $size } else { 0 }
      Update-ProgressTable @{ Pct = $pct; Done = $cur; Size = $size; Speed = $speed; Left = $(if ($speed -gt 1KB -and $size -gt 0) { [math]::Max(0.0, $size - $cur) / $speed } else { -1 }) }
    }
    $p.WaitForExit()
    $code = $p.ExitCode
    if ($code -eq 0) { break }
    Write-Host "   retry $try (curl error $code)..." -ForegroundColor Yellow; Start-Sleep 5
  }
  if ($code -ne 0) { throw "Download failed (curl error $code): $url" }
  if ($stage) {
    Write-Host "   copying $(Split-Path $dest -Leaf) to the drive..."
    Copy-WithProgress $fetch $part
    Remove-Item -Force $fetch
  }
  Move-Item -Force $part $dest
  $script:prog.Done += (Get-Item $dest).Length
  Show-Progress -Force
  Update-ProgressTable @{ Pct = 100; Done = (Get-Item $dest).Length; Size = (Get-Item $dest).Length; Speed = $speed; Left = 0 } -Force
  Write-Overall
}

function Expand-Any($archive, $dest) {
  New-Item -ItemType Directory -Force $dest | Out-Null
  if ($archive -like '*.zip') {
    # .NET's unzip copes with names Windows tar rejects (e.g. the map font folders)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $dest)
    return
  }
  # Windows tar (bsdtar) handles .tar.gz, but can't create the symlinks
  # in the Mac/Linux builds (and exFAT can't store them), so those become plain copies below
  $links = @(& tar.exe -tvf $archive | ForEach-Object { if ($_ -match '^l.*\s(\S+) -> (\S+)$') { @{ Name = $Matches[1]; Target = $Matches[2] } } })
  $ErrorActionPreference = 'Continue'   # PowerShell 5.1 turns redirected native stderr into errors
  & tar.exe -xf $archive -C $dest 2>$null
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0 -and $links.Count -eq 0) { throw "Could not extract $archive" }
  # links can point at other links (libggml.dylib -> libggml.0.dylib -> libggml.0.28.0.dylib)
  for ($pass = 0; $pass -lt 5 -and $links.Count; $pass++) {
    $links = @($links | Where-Object {
      $link = Join-Path $dest $_.Name
      $src = Join-Path (Split-Path $link) $_.Target
      if (Test-Path $src -PathType Leaf) { Copy-Item -Force $src $link; $false } else { $true }
    })
  }
}

# Copy the folder holding $exeName (wherever it sits inside the archive) flat into $dest
function Install-Flat($archive, $exeName, $dest) {
  $x = Join-Path $Tmp ('x-' + [guid]::NewGuid())
  Expand-Any $archive $x
  $exe = Get-ChildItem $x -Recurse -File | Where-Object { $_.Name -eq $exeName -or $_.Name -eq "$exeName.exe" } | Select-Object -First 1
  if (-not $exe) { throw "$exeName not found in $archive" }
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item -Recurse -Force (Join-Path $exe.DirectoryName '*') $dest
  Remove-Item -Recurse -Force $x
}

function Write-Json($value, $path) {
  # Set-Content -Encoding utf8 adds a BOM in PowerShell 5.1; browsers' JSON parser tolerates it, but keep files clean
  [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $value -Depth 5), (New-Object Text.UTF8Encoding $false))
}

function Write-Indexes {
  $docs = Join-Path $Target 'portal\docs'
  New-Item -ItemType Directory -Force $docs | Out-Null
  $list = @(Get-ChildItem $docs -Recurse -File | Where-Object { $_.Name -ne 'index.json' } | ForEach-Object {
    @{ path = $_.FullName.Substring($docs.Length + 1).Replace('\', '/'); size = $_.Length }
  })
  Write-Json $list (Join-Path $docs 'index.json')
  Write-Host "   docs: $($list.Count) file(s)"

  $maps = Join-Path $Target 'portal\maps'
  New-Item -ItemType Directory -Force $maps | Out-Null
  # zooms and bounds from each header, so the map page can show a map over 2 GB through the map server
  # (Windows llama-server can't send files that big) without reading the file itself
  $list = @(Get-ChildItem $maps -Filter *.pmtiles -File | ForEach-Object {
    $e = @{ name = $_.BaseName; file = $_.Name; size = $_.Length }
    $h = Read-Head $_.FullName 127
    if ($h.Length -ge 118 -and [Text.Encoding]::ASCII.GetString($h, 0, 7) -eq 'PMTiles') {
      $e.minzoom = [int]$h[100]; $e.maxzoom = [int]$h[101]
      $e.bounds = @(102, 106, 110, 114 | ForEach-Object { [BitConverter]::ToInt32($h, $_) / 1e7 })
    }
    $e
  })
  Write-Json $list (Join-Path $maps 'index.json')
  Write-Host "   maps: $(($list | ForEach-Object { $_.name }) -join ', ')"
}

# pmtiles CLI (only needed while building): cuts regions out of the daily OpenStreetMap planet file
function Get-PmtilesTool {
  $exe = Join-Path $Tmp 'pmtiles\pmtiles.exe'
  if (Test-Path $exe) { return $exe }
  $rel = Invoke-RestMethod 'https://api.github.com/repos/protomaps/go-pmtiles/releases/latest'
  $asset = $rel.assets | Where-Object { $_.name -like '*_Windows_x86_64.zip' } | Select-Object -First 1
  $zip = Join-Path $Tmp $asset.name
  Download $asset.browser_download_url $zip
  Expand-Any $zip (Join-Path $Tmp 'pmtiles')
  return $exe
}

function Read-Head($file, $n) {   # the first $n bytes of a file (a header), even while it is being written
  $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
  try { $b = New-Object byte[] $n; [void]$fs.Read($b, 0, $n); , $b } finally { $fs.Close() }
}

# Windows llama-server can't send files over 2 GB (404), so START-WINDOWS.bat serves big maps as tiles
# with the same pmtiles tool ("pmtiles serve", on port 8092). Only kits with such a map get it (56 MB).
$BigMap = 2GB - 1MB
$MapServer = 'tools\win\pmtiles.exe'
function Test-NeedsMapServer {
  [bool](Get-ChildItem (Join-Path $Target 'portal\maps') -Filter *.pmtiles -File -ErrorAction SilentlyContinue | Where-Object Length -ge $BigMap)
}
function Install-MapServer {
  $dst = Join-Path $Target $MapServer
  if ((Test-Path $dst) -or -not (Test-NeedsMapServer)) { return }
  New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
  Copy-Item -Force (Get-PmtilesTool) $dst
  Write-Host '   map server for big maps on Windows: tools\win\pmtiles.exe'
}

function Invoke-Pmtiles([string[]]$argList) {
  $ErrorActionPreference = 'Continue'   # it logs progress on stderr
  $out = & (Get-PmtilesTool) @argList 2>&1 | ForEach-Object { "$_" }
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { throw "pmtiles failed: $($out | Select-Object -Last 3)" }
  $out
}

# Cut a map in the background. Progress = bytes the map tool has written so far (its own "NN%" only
# changes when big chunks finish, so on a large map it can sit at 0% for many minutes).
# Returns $true when done, or the reason it failed (stuck: no map data for $StallMinutes; or the map
# tool's own error, e.g. a dropped connection), so the caller can try again.
$StallMinutes = 10
function Invoke-PmtilesWatched([string[]]$argList, $expected) {
  $log = Join-Path $Tmp 'pmtiles-progress.log'
  $quoted = $argList | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
  $p = Start-Process (Get-PmtilesTool) -ArgumentList $quoted -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  $null = $p.Handle
  Add-ChildProcess $p
  $written = 0.0; $lastGrowth = Get-Date; $speed = 0.0; $prevW = 0.0; $prevT = Get-Date
  Start-ProgressTable 'This map'
  while (-not $p.HasExited) {
    Start-Sleep -Milliseconds 700
    $w = [double](Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).WriteTransferCount
    if ($w -gt $written) { $written = $w; $lastGrowth = Get-Date }
    $dt = ((Get-Date) - $prevT).TotalSeconds
    if ($dt -ge 2) { $now = ($written - $prevW) / $dt; $speed = if ($speed -gt 0) { 0.7 * $speed + 0.3 * $now } else { $now }; $prevW = $written; $prevT = Get-Date }
    $done = [math]::Min($written, $expected * 0.999)
    Show-Progress $done
    Update-ProgressTable @{ Pct = $(if ($expected -gt 0) { 100.0 * $done / $expected } else { Get-LastPercent $log }); Done = $done; Size = $expected
      Speed = $speed; Left = $(if ($speed -gt 1KB) { [math]::Max(0.0, $expected - $done) / $speed } else { -1 }) }
    if (((Get-Date) - $lastGrowth).TotalMinutes -ge $StallMinutes) {
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      return "no map data for $StallMinutes minutes (the map server may be slow or busy)"
    }
  }
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) {
    # the tool's own error, without its progress-bar noise
    $why = @(Get-Content $log, "$log.err" -ErrorAction SilentlyContinue | ForEach-Object { ($_ -split "`r")[-1] } |
      Where-Object { $_ -match 'Failed|error|refused|aborted|timeout|reset' }) | Select-Object -Last 1
    if (-not $why) { $why = "map tool error $($p.ExitCode)" }
    return ($why -replace '^.*main\.go:\d+:\s*', '')
  }
  Update-ProgressTable @{ Pct = 100; Done = $expected; Size = $expected; Speed = $speed; Left = 0 } -Force
  $true
}

# ---------------------------------------------------------------- staging on this computer's disk
# Maps: the map tool writes the file in random order, and on a slow USB stick Windows first fills the whole
# file with zeros (minutes to hours for a big map). Downloads: a very slow stick can be slower than the
# internet. Either can be prepared on this computer's disk and then copied to the drive in one go.
# Decided once per build by Set-Staging (from -Staging and, for auto, a short write-speed test).
$script:stageMaps = $false; $script:stageFiles = $false
$FastDrive = 150   # MB/s: maps go straight to a drive at least this fast (a fast USB SSD, 10 Gbps port)
$SlowDrive = 25    # MB/s: downloads are prepared on this computer for a drive slower than this

# write speed of the target drive: write-through (no cache) for about 3 seconds
function Test-DriveSpeed {
  $f = Join-Path $Tmp 'speed-test.tmp'
  $buf = New-Object byte[] (8MB); (New-Object Random).NextBytes($buf)
  $fs = New-Object IO.FileStream($f, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
  $sw = [Diagnostics.Stopwatch]::StartNew(); $n = 0.0
  try { while ($sw.Elapsed.TotalSeconds -lt 3 -and $n -lt 1GB) { $fs.Write($buf, 0, $buf.Length); $n += $buf.Length }; $fs.Flush($true) }
  finally { $fs.Close(); $sw.Stop(); Remove-Item $f -Force -ErrorAction SilentlyContinue }
  $n / 1MB / [math]::Max(0.001, $sw.Elapsed.TotalSeconds)
}

function Set-Staging {
  $temp = [IO.Path]::GetFullPath($env:TEMP)
  if ($temp.Substring(0, 1) -eq $Target.Substring(0, 1)) { Write-Host '   Download method: straight to the folder (it is on this computer''s disk)'; return }
  switch ($Staging) {
    'local'  { $script:stageMaps = $true; $script:stageFiles = $true; Write-Host '   Download method: prepare on this computer, then copy to the drive' }
    'direct' { Write-Host '   Download method: straight to the drive' }
    default {
      $mbps = Test-DriveSpeed
      $script:stageMaps = $mbps -lt $FastDrive; $script:stageFiles = $mbps -lt $SlowDrive
      $how = if (-not $script:stageMaps) { 'fast drive: everything goes straight to it' }
             elseif (-not $script:stageFiles) { 'maps are prepared on this computer and copied over; downloads go straight to the drive' }
             else { 'slow drive: maps and downloads are prepared on this computer and copied over' }
      Write-Host ("   Drive write speed: {0:N0} MB/s - {1}" -f $mbps, $how)
    }
  }
}

# folder on this computer's disk for staging $size bytes, or $null (= straight to the drive)
function Get-StageDir([double]$size, $what) {
  $temp = [IO.Path]::GetFullPath($env:TEMP)
  if ($temp.Substring(0, 1) -eq $Target.Substring(0, 1)) { return }
  if ((Get-PSDrive $temp.Substring(0, 1)).Free -lt $size * 1.1 + 2GB) {
    Write-Host "   (not enough room on this computer's disk for $what; it goes straight to the drive)" -ForegroundColor Yellow; return
  }
  $dir = Join-Path $temp 'survival-station-staging'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $dir
}
function Get-MapWorkDir([double]$size) { if ($script:stageMaps) { Get-StageDir $size 'this map' } }

# copy a big file with the progress table (a plain Move-Item to a USB stick shows nothing for minutes)
function Copy-WithProgress($src, $dst) {
  $size = (Get-Item $src).Length
  Start-ProgressTable 'Copying'
  $in = [IO.File]::OpenRead($src); $out = [IO.File]::Create($dst)
  try {
    $buf = New-Object byte[] (4MB); $done = 0.0; $t0 = Get-Date; $shown = [datetime]::MinValue
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
      $out.Write($buf, 0, $n); $done += $n
      if (((Get-Date) - $shown).TotalMilliseconds -ge 500) {
        $shown = Get-Date; $secs = ((Get-Date) - $t0).TotalSeconds; $speed = if ($secs -gt 0) { $done / $secs } else { 0 }
        Update-ProgressTable @{ Pct = 100.0 * $done / $size; Done = $done; Size = $size; Speed = $speed; Left = $(if ($speed -gt 0) { ($size - $done) / $speed } else { -1 }) }
      }
    }
  } finally { $in.Close(); $out.Close() }
  Update-ProgressTable @{ Pct = 100; Done = $size; Size = $size; Speed = 0; Left = 0 } -Force
}

function Get-MapArgs($m, $planet, $out) {
  $a = @('extract', $planet, $out, "--maxzoom=$($m.MaxZoom)", '--download-threads=8')
  if ($m.Region) {
    # a country outline: GeoJSON polygon file for the map tool (first point repeated to close the ring)
    $pts = @($m.Region) + @($m.Region)[0]
    $file = Join-Path $Tmp "region-$($m.Name).geojson"
    $ring = ($pts | ForEach-Object { "[$_]" }) -join ','
    [IO.File]::WriteAllText($file, "{`"type`":`"Polygon`",`"coordinates`":[[$ring]]}")
    $a += "--region=$file"
  } elseif ($m.Bbox) { $a += "--bbox=$($m.Bbox)" }
  $a
}

# max zoom stored in a PMTiles v3 header (byte 101), so an update keeps the detail the map was built with
function Get-PmMaxZoom($file) {
  $fs = [IO.File]::OpenRead($file)
  try { $h = New-Object byte[] 127; [void]$fs.Read($h, 0, 127); if ([Text.Encoding]::ASCII.GetString($h, 0, 7) -eq 'PMTiles') { [int]$h[101] } } finally { $fs.Close() }
}

# newest llama.cpp release that has binaries (the newest can be a placeholder without them)
function Get-LlamaRelease { (Invoke-RestMethod 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10') | Where-Object { $_.assets.Count -gt 10 } | Select-Object -First 1 }

function Get-PmSize($log) {
  if (($log -join "`n") -match 'archive size of ([\d.]+) (kB|MB|GB)') { [int64]([double]$Matches[1] * @{ kB = 1KB; MB = 1MB; GB = 1GB }[$Matches[2]]) } else { 0 }
}

# newest daily planet build
function Get-Planet {
  $builds = Invoke-RestMethod 'https://build-metadata.protomaps.dev/builds.json'   # assign first: PS 5.1 doesn't unroll JSON arrays in a pipeline
  ($builds | ForEach-Object { $_.key } | Sort-Object)[-1]
}

# newest edition of a ZIM on the mirror -> @{ File; Url }, or nothing
$script:zimDirs = @{}
function Find-Zim($z) {
  if (-not $script:zimDirs[$z.Dir]) { $script:zimDirs[$z.Dir] = (Invoke-WebRequest "https://download.kiwix.org/zim/$($z.Dir)/" -UseBasicParsing).Links.href }
  $file = $script:zimDirs[$z.Dir] | Where-Object { $_ -match ('^' + [regex]::Escape($z.Prefix) + '_\d{4}-\d{2}\.zim$') } | Sort-Object | Select-Object -Last 1
  if ($file) { @{ File = $file; Url = "https://download.kiwix.org/zim/$($z.Dir)/$file" } }
}

# Android APKs to sideload -> @{ Name; Url; Size }
function Get-AppList {
  $kiwixApk = (Invoke-WebRequest 'https://download.kiwix.org/release/kiwix-android/' -UseBasicParsing).Links.href |
    Where-Object { $_ -match '^org\.kiwix\.kiwixmobile\.standalone-v?[\d.]+\.apk$' } |
    Sort-Object { [version]([regex]::Match($_, '([\d.]+)\.apk$').Groups[1].Value.TrimEnd('.')) } | Select-Object -Last 1
  if ($kiwixApk) {
    $url = "https://download.kiwix.org/release/kiwix-android/$kiwixApk"
    @{ Name = 'Kiwix.apk'; Url = $url; Size = Get-RemoteSize $url }
  }
  foreach ($app in @(@{ Repo = 'a-ghorbani/pocketpal-ai'; Name = 'PocketPal-AI.apk' }, @{ Repo = 'organicmaps/organicmaps'; Name = 'OrganicMaps.apk' })) {
    try {
      $a = (Invoke-RestMethod "https://api.github.com/repos/$($app.Repo)/releases/latest").assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1
      if ($a) { @{ Name = $app.Name; Url = $a.browser_download_url; Size = [int64]$a.size } }
    } catch { Write-Host "   (skipped $($app.Name): $($_.Exception.Message))" -ForegroundColor Yellow }
  }
}

# ---------------------------------------------------------------- main

if ($IndexOnly) { Write-Indexes; exit }

if ($Catalog) {
  # everything the builder window can offer, with today's sizes (maps at zoom 15, measured in parallel)
  New-Item -ItemType Directory -Force $Tmp | Out-Null
  $planet = "https://build.protomaps.com/$(Get-Planet)"
  $pm = Get-PmtilesTool
  $runs = foreach ($name in @('world') + @($MapPresets.Keys)) {
    $m = if ($name -eq 'world') { @{ Name = 'world'; Bbox = ''; MaxZoom = 7 } } else { @{ Name = $name; Bbox = $MapPresets[$name]; Region = $MapRegions[$name]; MaxZoom = 15 } }
    $log = Join-Path $Tmp "dry-$name.log"
    $argList = (Get-MapArgs $m $planet "dry-$name.pmtiles") + '--dry-run' | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
    @{ Name = $name; Log = $log; P = Start-Process $pm -ArgumentList $argList `
         -WorkingDirectory $Tmp -RedirectStandardError $log -RedirectStandardOutput "$log.out" -NoNewWindow -PassThru }
  }
  $list = @()
  foreach ($m in $Models) {
    $size = (Get-RemoteSize $m.Url) + $(if ($m.Mmproj) { Get-RemoteSize $m.Mmproj } else { 0 })
    $list += [ordered]@{ id = $m.Id; group = 'model'; name = $m.Name; tier = $m.Tier; file = "models/$($m.File)"; size = $size }
  }
  foreach ($z in $Zims) {
    $f = Find-Zim $z
    if (-not $f) { continue }
    $list += [ordered]@{ id = $z.Prefix; group = 'zim'; name = $z.Name; tier = $z.Tier; lang = $z.Lang; notIn = "$($z.NotIn)"; opt = [bool]$z.Opt
                         file = "library/$($f.File)"; size = Get-RemoteSize $f.Url }
  }
  $apps = @(Get-AppList)
  $list += [ordered]@{ id = 'survival-data'; group = 'extra'; name = 'Survival-Data: preparedness, radio, medical PDFs (third-party books with no stated licence: your choice)'; file = 'portal/survival-data/index.html'; size = 1500MB }
  $list += [ordered]@{ id = 'voice'; group = 'extra'; name = 'Voice: speak questions to the AI, also on phones (Windows, Linux)'; file = ($WhisperModelFile -replace '\\', '/'); size = (Get-RemoteSize $WhisperModel) + 210MB }   # + speech servers (~20 MB) and Caddy (~50 MB) per system
  $list += [ordered]@{ id = 'apps'; group = 'extra'; name = 'Android apps: Kiwix, PocketPal AI, Organic Maps'; file = 'apps/android/Kiwix.apk'; size = [int64]($apps | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum }
  $world = 0
  foreach ($r in $runs) {
    $r.P.WaitForExit()
    $size = Get-PmSize ((Get-Content $r.Log, "$($r.Log).out" -ErrorAction SilentlyContinue))
    Remove-Item $r.Log, "$($r.Log).out" -ErrorAction SilentlyContinue
    if ($r.Name -eq 'world') { $world = $size; continue }
    $label = $MapLabels[$r.Name]
    if (-not $label) { $label = (Get-Culture).TextInfo.ToTitleCase($r.Name.Replace('-', ' ')) }
    $list += [ordered]@{ id = $r.Name; group = 'map'; name = $label; file = "portal/maps/$($r.Name).pmtiles"; size = $size }
  }
  # newest versions, for the window's update check
  $engine = try { (Get-LlamaRelease).tag_name } catch { '' }
  $sdPushed = try { "$((Invoke-RestMethod 'https://api.github.com/repos/PR0M3TH3AN/Survival-Data').pushed_at)" } catch { '' }
  # which items include others (the window greys those out instead of letting both be ticked)
  foreach ($i in $list) { $i.contains = @($Contains[$i.id] | Where-Object { $_ }) }
  Write-Json ([ordered]@{ version = 4; retired = $Retired; created = (Get-Date).ToString('s'); planet = $planet; pmtiles = $pm; engine = $engine; sdPushed = $sdPushed; base = $BaseSize - 190MB + $world; items = $list }) $Catalog
  Write-Host "   $($list.Count) items -> $Catalog"
  exit
}

if ($Verify) {
  # ------------------------------------------------------------ verify / repair
  Step "Checking the kit in $Target"
  $script:found = @()
  function Report($state, $text, $fix = $null) {
    $tag = @{ ok = '[OK]'; bad = '[!!]'; wait = '[..]'; info = '[  ]' }[$state]
    Write-Host "   $tag $text" -ForegroundColor (@{ ok = 'Green'; bad = 'Red'; wait = 'Yellow'; info = 'Gray' }[$state])
    $script:found += @{ State = $state; Fix = $fix }
  }
  $recent = (Get-Date).AddMinutes(-3)   # a .part written this recently is still downloading
  $busy = @(Get-ChildItem $Target -Recurse -File -Filter *.part -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $recent }).Count -gt 0
  if (-not (Test-Path (Join-Path $Target 'START-WINDOWS.bat'))) { throw "No Survival Station kit in $Target. Build it first." }

  $kitVersion = Get-AppVersion $Target
  Report info ("App version on the kit: {0}   (this builder: {1})" -f $(if ($kitVersion) { $kitVersion } else { 'before 1.0.0' }), $AppVersion)
  # app files: newer or missing compared with this builder's folder
  if ((Norm-Path $Root) -ne (Norm-Path $Target)) {
    $old = @(Get-AppFiles | Where-Object {
      $src = Get-Item (Join-Path $Root $_); $dst = Join-Path $Target $_
      -not (Test-Path $dst) -or (Get-Item $dst).Length -ne $src.Length -or $src.LastWriteTime -gt (Get-Item $dst).LastWriteTime.AddSeconds(2) })
    if (-not (Test-Path (Join-Path $Target 'models\PHONE-AI-SETUP.txt'))) { $old += 'models\PHONE-AI-SETUP.txt' }
    if ($old) { Report bad "App pages and tools: $($old.Count) files missing or older than this builder's (e.g. $($old[0]))" @{ Kind = 'app' } }
    else { Report ok 'App pages, start files and tools are current' }
  }

  $miss = @($Engines.Values | Where-Object { -not (Get-ChildItem (Join-Path $Target "engine\$_") -Filter 'llama-server*' -ErrorAction SilentlyContinue) })
  if ($miss) { Report bad "AI engine missing for: $($miss -join ', ')" @{ Kind = 'delete'; Path = (Join-Path $Target 'engine\VERSION') } }
  else { Report ok "AI engine for $($Engines.Values -join ', ')" }

  $miss = @($KiwixBuilds.Values | ForEach-Object { $_.Folder } | Where-Object { -not (Get-ChildItem (Join-Path $Target "kiwix\$_") -Filter 'kiwix-serve*' -ErrorAction SilentlyContinue) })
  if ($miss) { foreach ($f in $miss) { Report bad "Library server missing for: $f" @{ Kind = 'delete'; Path = (Join-Path $Target "kiwix\$f") } } }
  else { Report ok 'Library server for every system' }

  $vendor = Join-Path $Target 'portal\vendor'
  if (@($Viewer.Keys | Where-Object { -not (Test-Path (Join-Path $vendor $_)) }) -or -not (Test-Path (Join-Path $vendor 'basemaps-assets\fonts'))) { Report bad 'Map viewer files missing' @{ Kind = 'run' } }
  else { Report ok 'Map viewer' }

  # AI models: GGUF header; size against the download when online
  $ggufs = @(Get-ChildItem (Join-Path $Target 'models') -Filter *.gguf -ErrorAction SilentlyContinue)   # not $models: names ignore case and $Models is the catalogue
  if (-not $ggufs) { Report bad 'No AI model in models\' }
  foreach ($f in $ggufs) {
    $known = $Models | Where-Object { $_.File -eq $f.Name } | Select-Object -First 1
    $magic = [Text.Encoding]::ASCII.GetString((Read-Head $f.FullName 4))
    $remote = if ($known) { Get-RemoteSize $known.Url } else { 0 }
    $fix = if ($known) { @{ Kind = 'item'; Id = $known.Id } }
    if ($magic -ne 'GGUF') { Report bad "AI model $($f.Name): damaged (not a GGUF file)" $(if ($fix) { $fix + @{ Delete = $f.FullName } }) }
    elseif ($remote -gt 0 -and $f.Length -ne $remote) { Report bad ("AI model {0}: incomplete ({1} of {2})" -f $f.Name, (Fmt-Size $f.Length), (Fmt-Size $remote)) $fix }
    else { Report ok ("AI model {0} ({1}{2})" -f $f.Name, (Fmt-Size $f.Length), $(if (-not $known) { ', your own model: size not checked' } elseif (-not $remote) { ', size not checked: offline' })) }
    if ($known.Mmproj) {   # its vision part
      $mm = Get-MmprojPath $known
      $mmRemote = Get-RemoteSize $known.Mmproj
      if (-not (Test-Path $mm)) { Report bad "AI model $($f.Name): photo reading part missing" $fix }
      elseif ($mmRemote -gt 0 -and (Get-Item $mm).Length -ne $mmRemote) { Report bad "AI model $($f.Name): photo reading part incomplete" $fix }
      else { Report ok "AI model $($f.Name): photo reading part" }
    }
  }

  # library: a complete ZIM ends exactly 16 bytes (its MD5) after the checksum position in its header
  $zimFiles = @(Get-ChildItem (Join-Path $Target 'library') -Filter *.zim -ErrorAction SilentlyContinue)
  if (-not $zimFiles) { Report bad 'No library books in library\' }
  $retiredFiles = @(Get-RetiredFiles)
  foreach ($r in $retiredFiles) { Report bad ("Library {0}: {1} - repair removes it" -f $r.File.Name, $r.Why) @{ Kind = 'remove'; Path = $r.File.FullName } }
  foreach ($f in $zimFiles) {
    if ($retiredFiles | Where-Object { $_.File.FullName -eq $f.FullName }) { continue }
    $h = Read-Head $f.FullName 80
    $z = $Zims | Where-Object { $f.Name -match ('^' + [regex]::Escape($_.Prefix) + '_\d{4}-\d{2}\.zim$') } | Select-Object -First 1
    $fix = if ($z) { @{ Kind = 'item'; Id = $z.Prefix } }
    if ([BitConverter]::ToUInt32($h, 0) -ne 72173914) { Report bad "Library $($f.Name): damaged (not a ZIM file)" $(if ($fix) { $fix + @{ Delete = $f.FullName } }) }
    elseif ($f.Length -ne [BitConverter]::ToUInt64($h, 72) + 16) { Report bad ("Library {0}: incomplete ({1})" -f $f.Name, (Fmt-Size $f.Length)) $fix }
    else { Report ok ("Library {0} ({1})" -f $f.Name, (Fmt-Size $f.Length)) }
  }
  foreach ($g in ($zimFiles | Group-Object { $_.Name -replace '_\d{4}-\d{2}\.zim$', '' } | Where-Object Count -gt 1)) {
    Report info "Library $($g.Name): $($g.Count) editions on the drive (the next update keeps only the newest)"
  }

  # maps: a complete PMTiles file reaches the end of its tile data
  $mapFiles = @(Get-ChildItem (Join-Path $Target 'portal\maps') -Filter *.pmtiles -ErrorAction SilentlyContinue)
  if (-not ($mapFiles | Where-Object BaseName -eq 'world')) { Report bad 'World map missing' @{ Kind = 'run' } }
  foreach ($f in $mapFiles) {
    $h = Read-Head $f.FullName 127
    $preset = $MapPresets.Contains($f.BaseName) -or $f.BaseName -eq 'world'
    $fix = if ($preset) { @{ Kind = $(if ($f.BaseName -eq 'world') { 'run' } else { 'item' }); Id = $f.BaseName; Delete = $f.FullName } }
    if ([Text.Encoding]::ASCII.GetString($h, 0, 7) -ne 'PMTiles') { Report bad "Map $($f.BaseName): damaged" $fix }
    elseif ($f.Length -lt [BitConverter]::ToUInt64($h, 56) + [BitConverter]::ToUInt64($h, 64)) { Report bad "Map $($f.BaseName): incomplete" $fix }
    else { Report ok ("Map {0} ({1}, zoom 0-{2})" -f $f.BaseName, (Fmt-Size $f.Length), $h[101]) }
    if (-not $preset -and $script:found[-1].State -eq 'bad') { Report info "   (your own area: delete it and add it again in the builder window)" }
  }
  if (-not (Test-Places)) { Report bad 'Place names for the map search missing, or made before a map was added' @{ Kind = 'run' } }
  if ((Test-NeedsMapServer) -and -not (Test-Path (Join-Path $Target $MapServer))) {
    Report bad 'Map server for maps over 2 GB missing (without it Windows shows only the world map)' @{ Kind = 'run' }
  }

  if (Test-Path (Join-Path $Target 'portal\survival-data\index.html')) {
    Report ok 'Survival-Data'
    if (-not (Test-PdfIndex)) { Report bad 'Survival-Data search index missing (the search can''t look inside the PDFs)' @{ Kind = 'run' } }
  }
  elseif (Test-Path (Join-Path $Target 'portal\survival-data')) { Report bad 'Survival-Data: incomplete' @{ Kind = 'item'; Id = 'survival-data'; Delete = (Join-Path $Target 'portal\survival-data') } }
  else { Report info 'Survival-Data not on this kit (tick it in the builder window to add it)' }
  if (-not (Test-Path (Join-Path $Target 'apps\android'))) { Report info 'Android apps not on this kit' }
  if (Test-Voice) { Report ok 'Voice (speech to text) for Windows and Linux' }
  elseif (Test-Path (Join-Path $Target 'models\whisper')) { Report bad 'Voice: part of it is missing' @{ Kind = 'item'; Id = 'voice' } }
  else { Report info 'Voice (speech to text) not on this kit (tick it in the builder window to add it)' }

  # chosen in BUILD-CHOICES.txt but never started (a stopped build): repair fetches them too
  $ch = Read-Choices
  if ($ch) {
    $parts = @(Get-ChildItem $Target -Recurse -File -Filter *.part -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.Replace('.part', '') })
    $notYet = @()
    foreach ($id in $ch.Items) {
      $m = $Models | Where-Object { $_.Id -eq $id } | Select-Object -First 1
      $z = $Zims | Where-Object { $_.Prefix -eq $id } | Select-Object -First 1
      $there = if ($m) { (Test-Path (Join-Path $Target "models\$($m.File)")) -or $parts -contains $m.File }
               elseif ($z) { (Test-Path (Join-Path $Target "library\$($z.Prefix)_*.zim")) -or @($parts | Where-Object { $_ -like "$($z.Prefix)_*.zim" }).Count }
               elseif ($MapPresets.Contains($id)) { (Test-Path (Join-Path $Target "portal\maps\$id.pmtiles")) -or $parts -contains "$id.pmtiles" }
               elseif ($id -eq 'survival-data') { Test-Path (Join-Path $Target 'portal\survival-data\index.html') }
               elseif ($id -eq 'apps') { Test-Path (Join-Path $Target 'apps\android') }
               elseif ($id -eq 'voice') { Test-Voice }
               else { $true }
      if (-not $there) { $notYet += $id }
    }
    if ($ch.Custom -and -not (Test-Path (Join-Path $Target "portal\maps\$($ch.Custom.Name).pmtiles"))) { $notYet += "map $($ch.Custom.Name)" }
    if ($notYet) {
      Report bad ("Chosen in BUILD-CHOICES.txt but not downloaded yet ({0}): {1}" -f $notYet.Count, ($notYet -join ', '))
      foreach ($id in $notYet) {
        if ($id -like 'map *') { $script:found += @{ State = 'info'; Fix = @{ Kind = 'custom'; Name = $ch.Custom.Name; Bbox = $ch.Custom.Bbox } } }
        else { $script:found += @{ State = 'info'; Fix = @{ Kind = 'item'; Id = $id } } }
      }
    } else { Report ok "Everything chosen in BUILD-CHOICES.txt is on the drive ($($ch.Items.Count) items)" }
  }

  foreach ($f in (Get-ChildItem $Target -Recurse -File -Filter *.part -ErrorAction SilentlyContinue)) {
    $name = $f.Name.Replace('.part', '')
    if ($f.LastWriteTime -gt $recent) { Report wait ("Downloading now: {0} ({1} so far)" -f $name, (Fmt-Size $f.Length)); continue }
    # which item it belongs to, so the update fetches it even though it isn't "on the kit" yet
    $id = ($Models | Where-Object { $_.File -eq $name } | ForEach-Object { $_.Id }) +
          ($Zims | Where-Object { $name -match ('^' + [regex]::Escape($_.Prefix) + '_\d{4}-\d{2}\.zim$') } | ForEach-Object { $_.Prefix }) +
          $(if ($name -match '^(.+)\.pmtiles$' -and $MapPresets.Contains($Matches[1])) { $Matches[1] }) | Select-Object -First 1
    Report wait ("Unfinished download: {0} ({1}) - repair finishes it" -f $name, (Fmt-Size $f.Length)) @{ Kind = 'run'; Id = $id }
  }
  $free = (Get-PSDrive ($Target.Substring(0, 1))).Free
  Report info ("Free space: {0}" -f (Fmt-Size $free))

  # ------------------------------------------------------------ summary and repair
  $bad = @($script:found | Where-Object { $_.State -eq 'bad' })
  $fixes = @($script:found | Where-Object { $_.Fix } | ForEach-Object { $_.Fix })
  Write-Host ("`n   {0} OK, {1} to fix, {2} downloading or unfinished" -f @($script:found | Where-Object State -eq 'ok').Count, $bad.Count, @($script:found | Where-Object State -eq 'wait').Count)
  if (-not $fixes) { Write-Host '   Nothing to repair.' -ForegroundColor Green; Write-Indexes; exit }
  $fetch = @($fixes | Where-Object { $_.Kind -notin 'app', 'remove' })
  $remove = @($fixes | Where-Object { $_.Kind -eq 'remove' })
  Write-Host "`n   Repair will:"
  if ($fixes | Where-Object Kind -eq 'app') { Write-Host '    - copy the newest app pages, start files and tools (no internet needed)' }
  if ($remove) { Write-Host "    - remove $($remove.Count) file(s) that don't belong in the kit (no internet needed)" }
  if ($fetch) { Write-Host '    - download again what is missing or incomplete, and finish unfinished downloads (needs internet)' }
  if ($fetch -and $busy) { Write-Host '      A download is running on this drive right now, so this part is skipped: run Verify again when it finishes.' -ForegroundColor Yellow }
  if (-not $Yes -and (Read-Host "`n   Repair now? [Y/n]") -match '^n') { exit }

  if ($fixes | Where-Object Kind -eq 'app') { Step 'Copying the newest app files'; Copy-AppFiles; Write-Host '   done' }
  foreach ($r in $remove) {
    try { Remove-Item -Force $r.Path -ErrorAction Stop; Write-Host "   removed $(Split-Path $r.Path -Leaf)" }
    catch { Write-Host "   could not remove $(Split-Path $r.Path -Leaf): close the kit (its library server has it open) and repair again" -ForegroundColor Yellow }
  }
  Write-Indexes
  if ($fetch -and -not $busy) {
    foreach ($f in $fetch) { if ($f.Delete -and (Test-Path $f.Delete)) { Remove-Item -Recurse -Force $f.Delete } elseif ($f.Path -and (Test-Path $f.Path)) { Remove-Item -Recurse -Force $f.Path } }
    $ids = @($fetch | Where-Object { $_.Id } | ForEach-Object { $_.Id } | Select-Object -Unique) + 'none'
    $more = @()
    $c = $fetch | Where-Object { $_.Kind -eq 'custom' } | Select-Object -First 1
    if ($c) { $more = @('-MapBbox', $c.Bbox, '-MapName', $c.Name) }
    if ($ch) { $more += @('-MapMaxZoom', $ch.Zoom) }   # new maps at the zoom the kit was built with
    Step 'Downloading what is missing (update mode)'
    try { Stop-Transcript | Out-Null } catch { }
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Drive $Target.TrimEnd('\') -Update -Items ($ids -join ',') -MapMaxAgeDays $MapMaxAgeDays -Yes @more
    exit $LASTEXITCODE
  }
  Step 'Repair finished'
  exit
}

$vol = Get-Volume -FilePath $Target -ErrorAction SilentlyContinue
if ($vol -and $vol.FileSystem -eq 'FAT32') {
  Write-Host "`nWARNING: $Target is FAT32, which cannot hold files over 4 GB (AI models, Wikipedia)." -ForegroundColor Red
  Write-Host "Reformat it as exFAT (works on Windows, Mac, Linux, Android) and run this again." -ForegroundColor Red
  exit 1
}

$what = if ($ItemSet) { "$($ItemSet.Count) chosen items" } else { "$Tier tier, languages: $($LangList -join ', ')" }
Write-Host "Survival Station builder $AppVersion"
Step "Planning ($what) -> $Target"
New-Item -ItemType Directory -Force $Tmp | Out-Null
$zimList = @()
foreach ($z in ($Zims | Where-Object { Wanted $_ $_.Prefix })) {
  $f = Find-Zim $z
  if (-not $f) { Write-Host "   (not found on mirror, skipping) $($z.Prefix)" -ForegroundColor Yellow; continue }
  $zimList += @{ File = $f.File; Url = $f.Url; Size = (Get-RemoteSize $f.Url); Prefix = $z.Prefix; Name = $z.Name }
}
$modelList = @($Models | Where-Object { Wanted $_ $_.Id } | ForEach-Object {
  $_.MainSize = Get-RemoteSize $_.Url
  $_.MmSize = if ($_.Mmproj) { Get-RemoteSize $_.Mmproj } else { 0 }
  $_.Size = $_.MainSize + $_.MmSize
  $_ })

# never two items where one includes the other (Canada + Canada south, complete Wikipedia + Wikipedia medicine...)
$chosen = @($zimList | ForEach-Object { $_.Prefix }) + @($MapList | ForEach-Object { $_.Name })
foreach ($id in $chosen) { $by = Get-Container $id $chosen; if ($by) { Write-Host "   (skipping $id - already included in $by)" -ForegroundColor Yellow } }
$zimList = @($zimList | Where-Object { -not (Get-Container $_.Prefix $chosen) })
$MapList = @($MapList | Where-Object { -not (Get-Container $_.Name $chosen) })

# maps: sizes from a dry run (reads only the index, takes seconds)
$planetBuild = Get-Planet
$planet = "https://build.protomaps.com/$planetBuild"
foreach ($m in $MapList) {
  $m.File = Join-Path $Target "portal\maps\$($m.Name).pmtiles"
  $m.Size = 0
  if ($Update -and (Test-Path $m.File)) {
    $m.Refresh = (Get-Item $m.File).LastWriteTime -lt (Get-Date).AddDays(-$MapMaxAgeDays)
    $z = Get-PmMaxZoom $m.File
    if ($z) { $m.MaxZoom = $z }
  }
  if ((Test-Path $m.File) -and -not $m.Refresh) { continue }
  $m.Size = Get-PmSize (Invoke-Pmtiles ((Get-MapArgs $m $planet 'dry-run.pmtiles') + '--dry-run'))
}

$total = if (Test-Path (Join-Path $Target 'engine\VERSION')) { 0 } else { $BaseSize }
if ($WantSD -and -not (Test-Path (Join-Path $Target 'portal\survival-data\index.html'))) { $total += 1500MB }
if ($WantApps -and -not (Test-Path (Join-Path $Target 'apps\android'))) { $total += 550MB }
if ($WantVoice -and -not (Test-Voice)) { $total += 400MB }
# files already on the target at the same size are skipped by Download, so they cost nothing
foreach ($m in $modelList) { $m.Have = (Test-Same (Join-Path $Target "models\$($m.File)") $m.MainSize) -and (-not $m.Mmproj -or (Test-Same (Get-MmprojPath $m) $m.MmSize)) }
foreach ($z in $zimList) { $z.Have = Test-Same (Join-Path $Target "library\$($z.File)") $z.Size }
foreach ($i in ($zimList + $modelList + $MapList)) { if (-not $i.Have) { $total += $i.Size } }
foreach ($m in $modelList) { "{0,8:N2} GB  AI model  {1} {2}" -f ($m.Size / 1GB), $m.Name, $(if ($m.Have) { '(already have)' }) }
foreach ($z in $zimList) { "{0,8:N2} GB  library   {1} {2}" -f ($z.Size / 1GB), $z.File, $(if ($z.Have) { '(already have)' }) }
foreach ($m in $MapList) {
  $note = if ($m.Refresh) { "(over $MapMaxAgeDays days old: refresh, zoom 0-$($m.MaxZoom))" } elseif (Test-Path $m.File) { '(already have)' } else { "(zoom 0-$($m.MaxZoom))" }
  "{0,8:N2} GB  map       {1} {2}" -f ($m.Size / 1GB), $m.Name, $note
}
$free = (Get-PSDrive ($Target.Substring(0, 1))).Free
"`n   Total ~{0:N1} GB, free on drive {1:N1} GB" -f ($total / 1GB), ($free / 1GB)
if ($total -gt $free) { Write-Host "   Not enough space (files already downloaded are counted, so this may still fit)." -ForegroundColor Yellow }
if (-not $Yes -and (Read-Host "`nContinue? [y/N]") -notmatch '^y') { exit }
$script:prog.Total = [double]$total
Show-Progress -Force
Write-Overall
if (-not $Update) { Write-Choices }
Set-Staging

Step 'Copying launchers and portal'
Copy-AppFiles

Step 'AI engine (llama.cpp) for Windows, Mac, Linux'
# the newest release can be a placeholder without binaries, so take the newest one that has them
$rel = Get-LlamaRelease
Write-Host "   llama.cpp $($rel.tag_name)"
$stamp = Join-Path $Target 'engine\VERSION'
if ((Test-Path $stamp) -and (Get-Content $stamp) -eq $rel.tag_name) { Write-Host '   ok (already have)' }
else {
  foreach ($suffix in $Engines.Keys) {
    $asset = $rel.assets | Where-Object { $_.name -like "llama-*-$suffix" } | Select-Object -First 1
    if (-not $asset) { Write-Host "   (no $suffix build this release)" -ForegroundColor Yellow; continue }
    $file = Join-Path $Tmp $asset.name
    Download $asset.browser_download_url $file
    Install-Flat $file 'llama-server' (Join-Path $Target "engine\$($Engines[$suffix])")
  }
  Set-Content $stamp $rel.tag_name
}

Step 'Library server (kiwix-serve) for Windows, Mac, Linux'
$kiwixFiles = (Invoke-WebRequest 'https://download.kiwix.org/release/kiwix-tools/' -UseBasicParsing).Links.href
foreach ($build in $KiwixBuilds.Keys) {
  $b = $KiwixBuilds[$build]
  $pattern = '^kiwix-tools_' + [regex]::Escape($build) + '-(\d+\.\d+\.\d+)(-\d+)?\.' + [regex]::Escape($b.Ext) + '$'
  $latest = $kiwixFiles | Where-Object { $_ -match $pattern } |
    Sort-Object { [version]([regex]::Match($_, $pattern).Groups[1].Value) }, { $_ } | Select-Object -Last 1
  if (-not $latest) { Write-Host "   (no kiwix build for $build)" -ForegroundColor Yellow; continue }
  $dest = Join-Path $Target "kiwix\$($b.Folder)"
  if (Test-Path (Join-Path $dest $latest)) { Write-Host "   ok (already have) $latest"; continue }
  $file = Join-Path $Tmp $latest
  Download "https://download.kiwix.org/release/kiwix-tools/$latest" $file
  Install-Flat $file 'kiwix-serve' $dest
  New-Item -ItemType File -Force (Join-Path $dest $latest) | Out-Null   # version marker
}

Step 'AI models'
foreach ($m in $modelList) {
  Download $m.Url (Join-Path $Target "models\$($m.File)")
  if ($m.Mmproj) { Download $m.Mmproj (Get-MmprojPath $m) }
}

Step 'Offline library (Kiwix ZIM files)'
$libDir = Join-Path $Target 'library'
foreach ($z in $zimList) {
  Download $z.Url (Join-Path $libDir $z.File)
  # remove older editions of the same archive
  Get-ChildItem $libDir -Filter "$($z.Prefix)_*.zim" | Where-Object { $_.Name -ne $z.File } | Remove-Item -Force
}
if ($Update) {
  foreach ($r in Get-RetiredFiles) {
    try { Remove-Item -Force $r.File.FullName -ErrorAction Stop; Write-Host "   removed $($r.File.Name): $($r.Why)" }
    catch { Write-Host "   could not remove $($r.File.Name): close the kit and update again" -ForegroundColor Yellow }
  }
}

Step 'Map viewer'
$vendor = Join-Path $Target 'portal\vendor'
foreach ($f in $Viewer.Keys) { Download $Viewer[$f] (Join-Path $vendor $f) }
$assets = Join-Path $vendor 'basemaps-assets'
if (Test-Path (Join-Path $assets 'fonts')) { Write-Host '   ok (already have) fonts and icons' }
else {
  $zip = Join-Path $Tmp 'basemaps-assets.zip'
  Download 'https://github.com/protomaps/basemaps-assets/archive/refs/heads/main.zip' $zip
  $x = Join-Path $Tmp 'ba'
  if (Test-Path $x) { Remove-Item -Recurse -Force $x }
  Expand-Any $zip $x
  $src = (Get-ChildItem $x -Directory | Select-Object -First 1).FullName
  New-Item -ItemType Directory -Force $assets | Out-Null
  Copy-Item -Recurse -Force (Join-Path $src 'fonts'), (Join-Path $src 'sprites') $assets
}

Step "Maps (OpenStreetMap via Protomaps, build $planetBuild)"
foreach ($m in $MapList) {
  if ((Test-Path $m.File) -and -not $m.Refresh) { Write-Host "   ok (already have - delete it to refresh) $($m.Name)"; continue }
  New-Item -ItemType Directory -Force (Split-Path $m.File) | Out-Null
  Write-Host "   extracting $($m.Name) (~$([math]::Round($m.Size / 1GB, 2)) GB)..."
  $part = "$($m.File).part"
  $work = Get-MapWorkDir $m.Size
  if ($work) { Get-ChildItem $work -File -ErrorAction SilentlyContinue | Remove-Item -Force }   # leftovers of a stopped build
  $cut = if ($work) { Join-Path $work "$($m.Name).pmtiles.part" } else { $part }
  $script:prog.Item = "map $($m.Name)"
  # a dropped connection or a stuck server: start the map again (the map tool can't resume), up to 3 tries
  for ($try = 1; ; $try++) {
    Remove-Item -Force $cut -ErrorAction SilentlyContinue
    $result = Invoke-PmtilesWatched (Get-MapArgs $m $planet $cut) $m.Size
    if ($result -eq $true) { break }
    Write-Host "   map $($m.Name) stopped: $result" -ForegroundColor Yellow
    if ($try -ge 3) { throw "Map $($m.Name) failed 3 times (last: $result). Check the internet connection and run the builder again; finished files are kept." }
    Write-Host "   trying the map again in 15 seconds (attempt $($try + 1) of 3)..."
    Start-Sleep 15
  }
  if ($work) {
    Write-Host "   copying $($m.Name) to the drive..."
    Remove-Item -Force $part -ErrorAction SilentlyContinue
    Copy-WithProgress $cut $part
    Remove-Item -Force $cut
  }
  Move-Item -Force $part $m.File
  $script:prog.Done += $m.Size
  Show-Progress -Force
  Write-Overall
}

$sdDest = Join-Path $Target 'portal\survival-data'
$sdStamp = Join-Path $sdDest '.version'   # GitHub's pushed_at of the copy we have
if ($WantSD) {
  Step 'Survival-Data (PR0M3TH3AN, ~1.5 GB)'
  $repo = Invoke-RestMethod 'https://api.github.com/repos/PR0M3TH3AN/Survival-Data'
  $sdCurrent = Test-Path (Join-Path $sdDest 'index.html')
  if ($sdCurrent -and $Update) {
    $sdCurrent = if (Test-Path $sdStamp) { (Get-Content $sdStamp) -eq "$($repo.pushed_at)" }
                 else { (Get-Item $sdDest).CreationTime -ge ([datetime]$repo.pushed_at).AddDays(-2) }   # unpacked folders carry the last commit's date, a little before the push
  }
}
if ($WantSD -and $sdCurrent) { Write-Host '   ok (already have the newest)' }
elseif ($WantSD) {
  $zip = Join-Path $Tmp 'survival-data.zip'
  Download "https://github.com/PR0M3TH3AN/Survival-Data/archive/refs/heads/$($repo.default_branch).zip" $zip
  $x = Join-Path $Tmp 'sd'
  if (Test-Path $x) { Remove-Item -Recurse -Force $x }
  Expand-Any $zip $x
  if (Test-Path $sdDest) { Remove-Item -Recurse -Force $sdDest }
  Move-Item (Get-ChildItem $x -Directory | Select-Object -First 1).FullName $sdDest
  Set-Content $sdStamp "$($repo.pushed_at)"
  Repair-SurvivalDataPage
}
# also for kits that already had Survival-Data (a new or updated copy removed the old index with its folder)
if ((Test-Path (Join-Path $sdDest 'index.html')) -and -not (Test-PdfIndex)) {
  Step 'Search index for the text inside the Survival-Data PDFs'
  Build-PdfIndex
}
if (-not (Test-Places)) {
  Step 'Place names for the map search (GeoNames)'
  Build-Places
}

if ($WantVoice) {
  Step 'Voice: speech to text (whisper.cpp) for Windows and Linux'
  Install-Voice
}

if ($WantApps) {
  Step 'Phone apps (Android APKs to sideload)'
  foreach ($a in Get-AppList) { Download $a.Url (Join-Path $Target "apps\android\$($a.Name)") }
}

Step 'Indexes'
Install-MapServer
Write-Indexes

Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $env:TEMP 'survival-station-staging') -ErrorAction SilentlyContinue   # everything is on the drive now

if ($Target.Length -gt 3) {
  # installed in a folder on this computer: add a desktop shortcut
  try {
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Survival Station.lnk'))
    $lnk.TargetPath = Join-Path $Target 'START-WINDOWS.bat'
    $lnk.WorkingDirectory = $Target
    $lnk.IconLocation = "$env:SystemRoot\System32\shell32.dll,23"
    $lnk.Save()
    Write-Host '   Desktop shortcut: Survival Station'
  } catch { Write-Host "   (no desktop shortcut: $($_.Exception.Message))" -ForegroundColor Yellow }
}
$script:prog.Item = 'finished'
Show-Progress -Force -State 'done'
Step "Done. Test it now while you still have internet: run $($Target)START-WINDOWS.bat"
Write-Host "   Log: $Log"
try { Stop-Transcript | Out-Null } catch { }
