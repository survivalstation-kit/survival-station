<#
.SYNOPSIS
  Survival Station builder window: tick what you want on the USB drive and see the space it needs.
  Opened by MAKE-USB.bat. Gets today's sizes with build-drive.ps1 -Catalog, builds with -Items.
  The portal's "My kit" page opens it with -Kit (that kit's folder) and -Action add | updates | verify.
  (Not -Drive: PowerShell names ignore case and $drive is the selected target below.)
#>
param([string]$Kit = '', [string]$Action = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
[Windows.Forms.Application]::EnableVisualStyles()

# One builder window at a time: opening MAKE-USB again brings the open window to the front instead
# (two windows reading the same busy drive made both freeze)
$script:single = New-Object Threading.Mutex($false, 'Local\SurvivalStationBuilderWindow')
$first = try { $script:single.WaitOne(0) } catch [Threading.AbandonedMutexException] { $true }   # abandoned = the old window was killed
if (-not $first) {
  Add-Type @'
using System; using System.Runtime.InteropServices;
public static class OtherWindow {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
  $other = Get-Process powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $PID -and $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match '^Survival Station .* - (build the USB drive|montar o pendrive)$' } | Select-Object -First 1
  if ($other) { [void][OtherWindow]::ShowWindow($other.MainWindowHandle, 6); [void][OtherWindow]::ShowWindow($other.MainWindowHandle, 9); [void][OtherWindow]::SetForegroundWindow($other.MainWindowHandle) }
  exit 0
}

$Builder = Join-Path $PSScriptRoot 'build-drive.ps1'
$PS = Join-Path $PSHOME 'powershell.exe'
$CacheFile = Join-Path $env:LOCALAPPDATA 'SurvivalStation\catalog.json'
$LogDir = Join-Path (Split-Path $PSScriptRoot) 'logs'   # build-drive.ps1 writes its logs here too
$WindowLog = Join-Path $LogDir 'builder-window.log'
function Get-AppVersion($folder) {   # from portal\version.js, the one place the version is set
  $f = Join-Path $folder 'portal\version.js'
  if ((Test-Path $f) -and ((Get-Content $f -Raw) -match "version:\s*'([^']+)'")) { $Matches[1] } else { '' }
}
$AppVersion = Get-AppVersion (Split-Path $PSScriptRoot)
$pt = (Get-UICulture).Name -like 'pt*'
function T($en, $ptText) { if ($pt) { $ptText } else { $en } }

$TierRank = @{ Lite = 1; Standard = 2; Full = 3 }
$Zooms = @(15, 14, 13)
$ZoomFactor = @{ 15 = 1.0; 14 = 0.5; 13 = 0.25 }   # measured: each zoom level less roughly halves a street map
$script:catalog = $null
$script:drive = $null       # selected target: a drive or a folder on this computer (see Load-Drives)
$script:updating = $false   # true while the code (not the user) ticks boxes

function Fmt([double]$b) {
  if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -gt 0) { '{0:N0} MB' -f [math]::Max(1.0, $b / 1MB) } else { '? GB' }
}
function Write-ErrorLog($err) {
  try {
    New-Item -ItemType Directory -Force $LogDir | Out-Null
    $where = if ($err.InvocationInfo) { " (line $($err.InvocationInfo.ScriptLineNumber): $($err.InvocationInfo.Line.Trim()))" }
    Add-Content -Encoding UTF8 $WindowLog "$((Get-Date).ToString('s'))  $($err.Exception.Message)$where"
  } catch { }
}
# event handlers: log and show errors instead of losing them in the hidden console
function Safe([scriptblock]$block) {
  try { & $block } catch {
    Write-ErrorLog $_
    [void][Windows.Forms.MessageBox]::Show(("$($_.Exception.Message)`n`n" + (T 'Saved in' 'Salvo em') + " $WindowLog"), 'Survival Station', 'OK', 'Error')
  }
}
function New-Ctl($type, [hashtable]$props = @{}) {
  $c = New-Object "Windows.Forms.$type"
  foreach ($k in $props.Keys) { $c.$k = $props[$k] }
  $c
}
function New-Row { New-Ctl FlowLayoutPanel @{ Dock = 'Top'; AutoSize = $true; WrapContents = $true; Padding = (New-Object Windows.Forms.Padding 4, 4, 4, 0) } }
function New-Label($text) { New-Ctl Label @{ Text = $text; AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 3, 7, 3, 0) } }

# ---------------------------------------------------------------- layout

$form = New-Ctl Form @{
  Text = "Survival Station $AppVersion - " + (T 'build the USB drive' 'montar o pendrive')
  Font = New-Object Drawing.Font('Segoe UI', 10); AutoScaleMode = 'Dpi'
  Size = New-Object Drawing.Size(940, 780); MinimumSize = New-Object Drawing.Size(640, 560); StartPosition = 'CenterScreen'
}

$row1 = New-Row
$cbDrive = New-Ctl ComboBox @{ DropDownStyle = 'DropDownList'; Width = 470 }
$btnDrives = New-Ctl Button @{ Text = (T 'Refresh' 'Atualizar'); AutoSize = $true }
$btnFolder = New-Ctl Button @{ Text = (T 'Folder...' 'Pasta...'); AutoSize = $true }
$btnFormat = New-Ctl Button @{ Text = (T 'Format as exFAT...' 'Formatar em exFAT...'); AutoSize = $true }
$lblWhere = New-Ctl Label @{ AutoSize = $true; ForeColor = [Drawing.Color]::DimGray; Margin = (New-Object Windows.Forms.Padding 3, 0, 3, 0) }
$row1.Controls.AddRange(@((New-Label (T 'Put it on:' 'Instalar em:')), $cbDrive, $btnDrives, $btnFolder, $btnFormat, $lblWhere))
$row1.SetFlowBreak($btnFormat, $true)

$row2 = New-Row
$btnLite = New-Ctl Button @{ Text = 'Lite'; AutoSize = $true }
$btnStd = New-Ctl Button @{ Text = 'Standard'; AutoSize = $true }
$btnFull = New-Ctl Button @{ Text = 'Full'; AutoSize = $true }
$chkEn = New-Ctl CheckBox @{ Text = 'English'; AutoSize = $true; Checked = $true; Margin = (New-Object Windows.Forms.Padding 12, 6, 3, 0) }
$chkPt = New-Ctl CheckBox @{ Text = 'Português'; AutoSize = $true; Checked = $pt; Margin = (New-Object Windows.Forms.Padding 3, 6, 3, 0) }
$btnNone = New-Ctl Button @{ Text = (T 'Untick all' 'Desmarcar tudo'); AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 12, 3, 3, 3) }
$row2.Controls.AddRange(@((New-Label (T 'Quick pick:' 'Escolha rápida:')), $btnLite, $btnStd, $btnFull, $chkEn, $chkPt, $btnNone))

$row3 = New-Row
$cbZoom = New-Ctl ComboBox @{ DropDownStyle = 'DropDownList'; Width = 215 }
[void]$cbZoom.Items.AddRange(@((T 'Every street (zoom 15)' 'Todas as ruas (zoom 15)'), (T 'Half the size (zoom 14)' 'Metade do tamanho (zoom 14)'), (T 'A quarter (zoom 13)' 'Um quarto (zoom 13)')))
$cbZoom.SelectedIndex = 0
$txtBox = New-Ctl TextBox @{ Width = 190 }
$txtName = New-Ctl TextBox @{ Width = 90; Text = (T 'my-area' 'minha-area') }
$btnArea = New-Ctl Button @{ Text = (T 'Add area' 'Adicionar'); AutoSize = $true }
$row3.Controls.AddRange(@((New-Label (T 'Map detail:' 'Detalhe do mapa:')), $cbZoom,
  (New-Label (T '  Other area (bboxfinder.com):' '  Outra área (bboxfinder.com):')), $txtBox, $txtName, $btnArea))

# how files reach the drive (build-drive.ps1 -Staging auto | local | direct)
$row4 = New-Row
$Stagings = @('auto', 'local', 'direct')
$cbStaging = New-Ctl ComboBox @{ DropDownStyle = 'DropDownList'; Width = 420 }
[void]$cbStaging.Items.AddRange(@((T 'Automatic (tests the drive''s speed)' 'Automático (testa a velocidade do pendrive)'),
  (T 'Prepare on this computer, then copy to the drive' 'Preparar neste computador e depois copiar para o pendrive'),
  (T 'Straight to the drive' 'Direto para o pendrive')))
$cbStaging.SelectedIndex = 0
$btnSpeed = New-Ctl Button @{ Text = (T 'Test drive speed' 'Testar velocidade'); AutoSize = $true }
$lblSpeed = New-Ctl Label @{ AutoSize = $true; ForeColor = [Drawing.Color]::DimGray; Margin = (New-Object Windows.Forms.Padding 6, 7, 3, 0) }
$row4.Controls.AddRange(@((New-Label (T 'Download method:' 'Como baixar:')), $cbStaging, $btnSpeed, $lblSpeed))
function Staging { $Stagings[[math]::Max(0, $cbStaging.SelectedIndex)] }

$tree = New-Ctl TreeView @{ Dock = 'Fill'; CheckBoxes = $true; ShowLines = $false; FullRowSelect = $true; ItemHeight = 24 }

$bottom = New-Ctl TableLayoutPanel @{ Dock = 'Bottom'; AutoSize = $true; ColumnCount = 1; Padding = (New-Object Windows.Forms.Padding 6) }
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle 'Percent', 100))
$lblNeed = New-Ctl Label @{ AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold) }
$lblFit = New-Ctl Label @{ AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 11) }
$bar = New-Ctl ProgressBar @{ Dock = 'Fill'; Height = 18; Maximum = 100 }
$lblStatus = New-Ctl Label @{ AutoSize = $true; ForeColor = [Drawing.Color]::DimGray }
$buttons = New-Ctl FlowLayoutPanel @{ Dock = 'Fill'; AutoSize = $true; FlowDirection = 'RightToLeft' }
$btnBuild = New-Ctl Button @{ Text = (T 'Build the drive' 'Montar o pendrive'); AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold) }
$btnTest = New-Ctl Button @{ Text = (T 'Test the drive' 'Testar o pendrive'); AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 3, 6, 3, 3) }
$btnSizes = New-Ctl Button @{ Text = (T 'Check sizes again' 'Conferir tamanhos de novo'); AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 3, 6, 3, 3) }
$btnLogs = New-Ctl Button @{ Text = (T 'Open logs' 'Abrir registros'); AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 3, 6, 3, 3) }
$btnUpdates = New-Ctl Button @{ Text = (T 'Check for updates' 'Procurar atualizações'); AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 3, 6, 3, 3) }
$btnCopy = New-Ctl Button @{ Text = (T 'Copy kit...' 'Copiar kit...'); AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 3, 6, 3, 3) }
$btnVerify = New-Ctl Button @{ Text = (T 'Verify / repair' 'Verificar / reparar'); AutoSize = $true; Margin = (New-Object Windows.Forms.Padding 3, 6, 3, 3) }
$buttons.Controls.AddRange(@($btnBuild, $btnTest, $btnVerify, $btnUpdates, $btnCopy, $btnSizes, $btnLogs))
# build status: follows logs\progress.json written by the running build (any window, even after reopening this one)
$buildPanel = New-Ctl TableLayoutPanel @{ Dock = 'Fill'; AutoSize = $true; ColumnCount = 1; Visible = $false; BackColor = [Drawing.Color]::FromArgb(236, 244, 255); Padding = (New-Object Windows.Forms.Padding 6) }
[void]$buildPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle 'Percent', 100))
$lblBuild = New-Ctl Label @{ AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 10.5, [Drawing.FontStyle]::Bold) }
$buildBar = New-Ctl ProgressBar @{ Dock = 'Fill'; Height = 22; Maximum = 100 }
$lblBuildItem = New-Ctl Label @{ AutoSize = $true; ForeColor = [Drawing.Color]::DimGray }
foreach ($c in $lblBuild, $buildBar, $lblBuildItem) { [void]$buildPanel.Controls.Add($c) }
foreach ($c in $buildPanel, $lblNeed, $lblFit, $bar, $lblStatus, $buttons) { [void]$bottom.Controls.Add($c) }

# docked controls are laid out last-added first
$form.Controls.AddRange(@($tree, $bottom, $row4, $row3, $row2, $row1))
$form.AcceptButton = $btnBuild

# ---------------------------------------------------------------- drives

# Targets: every USB/other drive, plus a folder on this computer (C:\Survival unless changed with "Folder...")
$script:folder = Join-Path $env:SystemDrive 'Survival'

function Load-Drives {
  $keep = if ($script:drive) { $script:drive.Name } else { $null }
  $cbDrive.Items.Clear()
  $script:targets = @()
  foreach ($v in (Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -and ("$($_.DriveLetter):" -ne $env:SystemDrive) -and $_.DriveType -in 'Removable', 'Fixed' } | Sort-Object DriveLetter)) {
    $bus = try { (Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop | Get-Disk).BusType } catch { '' }
    $label = if ($v.FileSystemLabel) { $v.FileSystemLabel } else { T 'no name' 'sem nome' }
    $script:targets += [pscustomobject]@{ Folder = $false; Letter = "$($v.DriveLetter)"; Name = "$($v.DriveLetter):"; Root = "$($v.DriveLetter):\"
      Free = $v.SizeRemaining; Size = $v.Size; FileSystem = $v.FileSystem; Label = $label; Usb = $bus -eq 'USB' }
  }
  $v = Get-Volume -DriveLetter $script:folder[0] -ErrorAction SilentlyContinue
  $script:targets += [pscustomobject]@{ Folder = $true; Letter = "$($script:folder[0])"; Name = $script:folder; Root = $script:folder.TrimEnd('\') + '\'
    Free = $v.SizeRemaining; Size = $v.Size; FileSystem = $v.FileSystem; Label = ''; Usb = $false }
  $pick = -1
  for ($i = 0; $i -lt $script:targets.Count; $i++) {
    $t = $script:targets[$i]
    $text = if ($t.Folder) { (T 'This computer, folder {0}  -  {1} free' 'Este computador, pasta {0}  -  {1} livres') -f $t.Name, (Fmt $t.Free) }
            else { '{0}  {1}  -  {2}  -  {3} {4} / {5}  {6}' -f $t.Name, $t.Label, $t.FileSystem, (Fmt $t.Free), (T 'free' 'livre'), (Fmt $t.Size), $(if ($t.Usb) { '(USB)' }) }
    [void]$cbDrive.Items.Add($text)
    if ($t.Name -eq $keep -or ($t.Folder -and $keep -and $script:drive.Folder)) { $pick = $i }
    elseif (-not $keep -and $t.Usb -and $pick -lt 0) { $pick = $i }
  }
  if ($pick -lt 0) { $pick = 0 }
  $cbDrive.SelectedIndex = $pick
  Update-Drive   # SelectedIndexChanged doesn't fire when the index stays the same
}

function Choose-Folder {
  $dlg = New-Ctl FolderBrowserDialog @{ Description = (T 'Folder for Survival Station on this computer (a new "Survival" folder is fine)' 'Pasta do Survival Station neste computador (uma pasta nova "Survival" serve)'); ShowNewFolderButton = $true }
  if (Test-Path $script:folder) { $dlg.SelectedPath = $script:folder } else { $dlg.SelectedPath = Split-Path $script:folder }
  if ($dlg.ShowDialog($form) -ne 'OK') { return }
  $p = $dlg.SelectedPath.TrimEnd('\')
  if ($p.Length -le 2) { $p = Join-Path $p 'Survival' }   # a whole drive root is picked: use a folder in it
  $script:folder = $p
  $script:drive = [pscustomobject]@{ Folder = $true; Name = $p }   # so Load-Drives selects the folder entry
  Load-Drives
}

# BUILD-CHOICES.txt on the target (written by build-drive.ps1 before downloading): tick the same items again
function Read-Choices($root) {
  $f = Join-Path $root 'BUILD-CHOICES.txt'
  if (-not (Test-Path $f)) { return }
  $lines = Get-Content $f -Encoding UTF8
  $at = [array]::IndexOf($lines, '# --- builder data (do not edit) ---')
  if ($at -lt 0) { return }
  $d = @{}
  foreach ($l in $lines[($at + 1)..($lines.Count - 1)]) { if ($l -match '^(\w+)=(.*)$') { $d[$Matches[1]] = $Matches[2].Trim() } }
  @{ Items = @("$($d.items)".Split(',', [StringSplitOptions]::RemoveEmptyEntries)); Zoom = $(if ($d.zoom -match '^\d+$') { [int]$d.zoom } else { 15 }); Custom = $d.custom; Stamp = (Get-Item $f).LastWriteTime }
}
# a half-finished download of this item on the target (a stopped build), as its .part file
function Get-Partial($item) {
  $r = Drive-Root
  if (-not $r) { return }
  $pattern = if ($item.group -eq 'zim') { Join-Path $r "library\$($item.id)_*.zim.part" } else { (Join-Path $r $item.file) + '.part' }
  Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
}
# on the target in any form: finished, an older edition, or partly downloaded
function Test-Present($item) { (On-Drive $item) -or (Old-Edition $item) -or (Get-Partial $item) }

# When a drive is chosen: tick what is already on it (finished, older edition or partly downloaded) plus what
# its BUILD-CHOICES.txt lists. Unticking never deletes anything from the drive, so this is always safe.
function Restore-Choices {
  $r = Drive-Root
  if (-not $script:catalog -or -not $r) { return }
  $ch = Read-Choices $r
  $present = @(Get-Leaves | Where-Object { $_.Tag.id -ne 'custom' -and (Test-Present $_.Tag) } | ForEach-Object { $_.Tag.id })
  if (-not $ch -and -not $present) { return }   # an empty drive keeps the default picks
  $key = "$r|$($ch.Stamp)|$($present.Count)"
  if ($script:restoredFor -eq $key) { return }   # once per drive, so the user's own changes stick
  $script:restoredFor = $key
  $chosen = @($present) + @($ch.Items)
  $script:updating = $true
  if ($ch) { $i = [array]::IndexOf($Zooms, $ch.Zoom); if ($i -ge 0) { $cbZoom.SelectedIndex = $i } }
  foreach ($n in (Get-Leaves)) {
    if ($n.Tag.id -eq 'custom') { continue }
    if (-not $ch -and $n.Tag.group -eq 'extra' -and $n.Checked) { continue }   # no choices file: ticked extras stay ticked (every tier gets them, and they download last)
    $n.Checked = $chosen -contains $n.Tag.id
  }
  if ($ch) { foreach ($n in @(Get-Leaves | Where-Object { $_.Tag.id -eq 'custom' })) { $n.Remove() } }
  if ($ch.Custom -match '^([^|]+)\|([^|]+)\|?(\d*)$') {
    $item = [pscustomobject]@{ id = 'custom'; group = 'map'; name = "$($Matches[1]) ($($Matches[2]))"; file = "portal/maps/$($Matches[1]).pmtiles"
      size = [double]("0$($Matches[3])") / $ZoomFactor[$ch.Zoom]; bbox = $Matches[2]; mapName = $Matches[1] }
    $n = $tree.Nodes['map'].Nodes.Add('custom', $item.name); $n.Tag = $item; $n.Checked = $true
  }
  $script:updating = $false
  $script:tier = $null
  Resolve-Overlaps; Relabel
  Sync-Groups; Update-Summary
  $count = @(Get-Leaves | Where-Object Checked).Count
  $lblStatus.Text = if ($ch) { (T 'Ticked the {0} items on this drive or in its BUILD-CHOICES.txt. Click "Build the drive" to finish anything missing.' 'Marcados os {0} itens que estão neste pendrive ou no BUILD-CHOICES.txt dele. Clique em "Montar o pendrive" para terminar o que falta.') -f $count }
                    else { (T 'Ticked the {0} items already on this drive (finished or partly downloaded). Tick anything else you want, then click "Build the drive".' 'Marcados os {0} itens que já estão neste pendrive (prontos ou pela metade). Marque o que mais quiser e clique em "Montar o pendrive".') -f $present.Count }
}

function Update-Drive {
  $script:drive = if ($script:targets -and $cbDrive.SelectedIndex -ge 0) { $script:targets[$cbDrive.SelectedIndex] } else { $null }
  $btnFormat.Enabled = $script:drive -and -not $script:drive.Folder
  $lblSpeed.Text = ''
  $lblWhere.Text = if ($script:drive.Folder) { T 'A copy on this computer works without the USB drive. A desktop shortcut is added.' 'Uma cópia neste computador funciona sem o pendrive. Um atalho é criado na área de trabalho.' } else { '' }
  $lblWhere.Visible = [bool]$lblWhere.Text
  foreach ($n in (Get-Leaves)) { Set-Label $n }
  Update-Summary
  Restore-Choices
}

function Drive-Root { if ($script:drive) { $script:drive.Root } }
function On-Drive($item) { $r = Drive-Root; $r -and (Test-Path (Join-Path $r $item.file)) }
# an older edition of a library book on the target (the builder replaces it with the newest)
function Old-Edition($item) {
  $r = Drive-Root
  if (-not $r -or $item.group -ne 'zim') { return }
  $new = Split-Path $item.file -Leaf
  Get-ChildItem (Join-Path $r 'library') -Filter "$($item.id)_*.zim" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $new } | Sort-Object Name | Select-Object -Last 1
}

# ---------------------------------------------------------------- the list

function Get-Leaves { foreach ($g in $tree.Nodes) { foreach ($n in $g.Nodes) { $n } } }
function Zoom { $Zooms[[math]::Max(0, $cbZoom.SelectedIndex)] }
function Item-Size($item) { if ($item.group -eq 'map') { $item.size * $ZoomFactor[(Zoom)] } else { $item.size } }

# Items that include others (catalog "contains"): never both ticked. Returns the ticked item that blocks $item:
# @{ How = 'in' (it already includes $item) | 'has' ($item includes it); Node }
function Get-Blocker($item) {
  foreach ($n in (Get-Leaves)) {
    if (-not $n.Checked -or $n.Tag.id -eq $item.id) { continue }
    if (@($n.Tag.contains) -contains $item.id) { return @{ How = 'in'; Node = $n } }
    if (@($item.contains) -contains $n.Tag.id) { return @{ How = 'has'; Node = $n } }
  }
}
# after the code ticks many boxes at once (tiers, a whole group, restored choices): keep the bigger item
function Resolve-Overlaps {
  $script:updating = $true
  foreach ($n in (Get-Leaves)) {
    if ($n.Checked -and (Get-Leaves | Where-Object { $_.Checked -and @($_.Tag.contains) -contains $n.Tag.id })) { $n.Checked = $false }
  }
  $script:updating = $false
}
function Relabel { foreach ($n in (Get-Leaves)) { Set-Label $n } }

function Set-Label($n) {
  $i = $n.Tag
  $n.Text = "$($i.name)   -   $(Fmt (Item-Size $i))"
  $b = if (-not $n.Checked) { Get-Blocker $i }
  if ($b -and $b.How -eq 'in') {
    # the smaller item: greyed out while a bigger ticked item already includes it
    $n.Text += '   ' + ((T '(already included in {0})' '(já incluído em {0})') -f $b.Node.Tag.name)
    $n.ForeColor = [Drawing.Color]::Silver
    return
  }
  if ($b) { $n.Text += '   ' + ((T '(replaces {0})' '(substitui {0})') -f $b.Node.Tag.name) }   # the bigger one: ticking it is an upgrade
  if (On-Drive $i) { $n.Text += '   ✓ ' + (T 'already there' 'já está lá'); $n.ForeColor = [Drawing.Color]::SeaGreen }
  elseif ($part = Get-Partial $i) {
    $n.Text += '   ⏸ ' + ((T 'partly downloaded ({0}): Build continues it' 'baixado pela metade ({0}): Montar continua') -f (Fmt $part.Length))
    $n.ForeColor = [Drawing.Color]::RoyalBlue
  }
  elseif (Old-Edition $i) { $n.Text += '   ⟳ ' + (T 'newer edition available' 'edição mais nova disponível'); $n.ForeColor = [Drawing.Color]::DarkOrange }
  else { $n.ForeColor = [Drawing.Color]::Empty }
}

function Fill-Tree {
  $tree.BeginUpdate()
  $was = @{}; foreach ($n in (Get-Leaves)) { $was[$n.Tag.id] = $n.Checked }
  $custom = Get-Leaves | Where-Object { $_.Tag.id -eq 'custom' } | ForEach-Object { $_.Tag }
  $tree.Nodes.Clear()
  $groups = [ordered]@{
    model = T 'AI models (pick at least one)' 'Modelos de IA (escolha pelo menos um)'
    en    = T 'Library - English' 'Biblioteca - inglês'
    pt    = T 'Library - Portuguese' 'Biblioteca - português'
    map   = T 'Street maps (a world map is always included)' 'Mapas de ruas (o mapa-mundi sempre vem)'
    extra = 'Extras'
  }
  foreach ($k in $groups.Keys) { [void]$tree.Nodes.Add($k, $groups[$k]) }
  $items = @($script:catalog.items) + @($custom | Where-Object { $_ })
  foreach ($i in $items) {
    $g = if ($i.group -eq 'zim') { $i.lang } else { $i.group }
    $n = $tree.Nodes[$g].Nodes.Add($i.id, $i.name)
    $n.Tag = $i
    if ($was.Count) { $n.Checked = [bool]$was[$i.id] }
    Set-Label $n
  }
  if (-not $was.Count) { Apply-Tier 'Lite' }
  Resolve-Overlaps; Relabel
  Sync-Groups
  $tree.ExpandAll()
  $tree.EndUpdate()
  if ($tree.Nodes.Count) { $tree.Nodes[0].EnsureVisible() }
}

function Sync-Groups {
  $script:updating = $true
  foreach ($g in $tree.Nodes) { $g.Checked = $g.Nodes.Count -gt 0 -and @($g.Nodes | Where-Object { -not $_.Checked }).Count -eq 0 }
  $script:updating = $false
}

# same choice the builder makes for -Tier/-Languages
function Apply-Tier($tier) {
  $langs = @(); if ($chkEn.Checked) { $langs += 'en' }; if ($chkPt.Checked) { $langs += 'pt' }
  $script:updating = $true
  foreach ($n in (Get-Leaves)) {
    $i = $n.Tag
    switch ($i.group) {
      'model' { $n.Checked = $TierRank[$i.tier] -le $TierRank[$tier] }
      'zim' { $n.Checked = $TierRank[$i.tier] -le $TierRank[$tier] -and ("$($i.notIn)".Split(',') -notcontains $tier) -and $langs -contains $i.lang -and -not $i.opt }
      'extra' { $n.Checked = $true }
    }
  }
  $script:updating = $false
  $script:tier = $tier
  Resolve-Overlaps; Relabel
  Sync-Groups
  Update-Summary
}

function Update-Summary {
  if (-not $script:catalog) { return }
  $root = Drive-Root
  $need = if ($root -and (Test-Path (Join-Path $root 'engine\VERSION'))) { 0 } else { [double]$script:catalog.base }
  $count = 0
  foreach ($n in (Get-Leaves)) {
    if (-not $n.Checked) { continue }
    $count++
    if (-not (On-Drive $n.Tag)) { $need += Item-Size $n.Tag }
  }
  $script:need = $need
  $script:fits = $true
  $stick = (8, 16, 32, 64, 128, 256, 512, 1024, 2048 | Where-Object { $_ * 1GB * 0.93 -ge $need } | Select-Object -First 1)
  $stickText = if ($stick -ge 1024) { "$($stick / 1024) TB" } elseif ($stick) { "$stick GB" } else { '> 2 TB' }
  $lblNeed.Text = (T '{0} to download  ({1} items, fits a {2} drive)' '{0} para baixar  ({1} itens, cabe num pendrive de {2})') -f (Fmt $need), $count, $stickText
  if (-not $script:drive) { $lblFit.Text = T 'Choose the USB drive above to see if it fits.' 'Escolha o pendrive acima para ver se cabe.'; $lblFit.ForeColor = [Drawing.Color]::DimGray; $bar.Value = 0; return }
  $free = [double]$script:drive.Free
  $bar.Value = [int][math]::Min(100.0, [math]::Round(100.0 * $need / [math]::Max(1.0, $free)))
  if ($need -le $free) {
    $lblFit.Text = (T '✓ Fits: {0} free on {1}:, {2} left over' '✓ Cabe: {0} livres em {1}:, sobram {2}') -f (Fmt $free), $script:drive.Letter, (Fmt ($free - $need))
    $lblFit.ForeColor = [Drawing.Color]::SeaGreen
  } else {
    $lblFit.Text = (T '✗ Too big: {1}: has {0} free. Untick {2}, use less map detail, or a bigger drive.' '✗ Não cabe: {1}: tem {0} livres. Desmarque {2}, use menos detalhe no mapa ou um pendrive maior.') -f (Fmt $free), $script:drive.Letter, (Fmt ($need - $free))
    $lblFit.ForeColor = [Drawing.Color]::Firebrick
    $script:fits = $false
  }
}

# ---------------------------------------------------------------- sizes (catalog)

function Load-Catalog {
  $script:catalog = Get-Content $CacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
  Fill-Tree
  $lblStatus.Text = (T 'Sizes checked online {0}. Already-downloaded files are not counted again.' 'Tamanhos conferidos {0}. Arquivos já baixados não contam de novo.') -f ([datetime]$script:catalog.created).ToString('g')
  Update-Summary
  Restore-Choices   # first load only; after "Check sizes again" Fill-Tree keeps the current ticks
}

$timer = New-Ctl Timer @{ Interval = 500 }
function Refresh-Catalog {
  New-Item -ItemType Directory -Force (Split-Path $CacheFile) | Out-Null
  $psi = New-Object Diagnostics.ProcessStartInfo $PS, ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Catalog "{1}.new"' -f $Builder, $CacheFile)
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  Remove-Item "$CacheFile.new" -ErrorAction SilentlyContinue
  $script:proc = [Diagnostics.Process]::Start($psi)
  $btnSizes.Enabled = $false
  $bar.Style = 'Marquee'
  $lblStatus.Text = T 'Checking today''s sizes online (about a minute)...' 'Conferindo os tamanhos atuais na internet (cerca de um minuto)...'
  $timer.Start()
}
$timer.Add_Tick({ Safe {
  if (-not $script:proc.HasExited) { return }
  $timer.Stop(); $bar.Style = 'Continuous'; $btnSizes.Enabled = $true
  if ($script:proc.ExitCode -eq 0 -and (Test-Path "$CacheFile.new")) {
    Move-Item -Force "$CacheFile.new" $CacheFile
    Load-Catalog
    if ($script:afterCatalog) { $next = $script:afterCatalog; $script:afterCatalog = $null; & $next }
    return
  }
  $log = Get-ChildItem $LogDir -Filter 'sizes-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  Write-ErrorLog @{ Exception = @{ Message = "size check failed (exit $($script:proc.ExitCode)), see $($log.Name)" } }
  $lblStatus.Text = if ($script:catalog) {
    T 'Could not check sizes (no internet?). Showing the last sizes. Details: Open logs.' 'Não deu para conferir (sem internet?). Mostrando os últimos tamanhos. Detalhes: Abrir registros.'
  } else {
    T 'Could not get the list. Connect to the internet and click "Check sizes again". Details: Open logs.' 'Não deu para baixar a lista. Conecte na internet e clique em "Conferir tamanhos de novo". Detalhes: Abrir registros.'
  }
} })

# ---------------------------------------------------------------- build status

$ProgressFile = Join-Path $LogDir 'progress.json'
function Fmt-Time([double]$s) {
  if ($s -lt 0) { return '?' }
  $t = [TimeSpan]::FromSeconds($s)
  if ($t.TotalDays -ge 1) { '{0}d {1}h' -f [int][math]::Floor($t.TotalDays), $t.Hours } elseif ($t.TotalHours -ge 1) { '{0}h {1:D2}m' -f [int][math]::Floor($t.TotalHours), $t.Minutes } elseif ($t.TotalMinutes -ge 1) { "$($t.Minutes) min" } else { '< 1 min' }
}
function Update-BuildStatus {
  $st = $null
  if (Test-Path $ProgressFile) { try { $st = [IO.File]::ReadAllText($ProgressFile) | ConvertFrom-Json } catch { return } }   # mid-write: try next tick
  if (-not $st -or ((Get-Date) - [datetime]$st.updated).TotalHours -gt 12) { $buildPanel.Visible = $false; $script:building = $false; return }
  $age = ((Get-Date) - [datetime]$st.updated).TotalSeconds
  $buildPanel.Visible = $true
  $buildBar.Value = [math]::Max(0, [math]::Min(100, [int]$st.percent))
  $where = $st.target
  $script:building = $false
  if ($st.state -eq 'done') {
    $lblBuild.Text = (T '✓ Build finished: {0}' '✓ Montagem concluída: {0}') -f $where; $lblBuild.ForeColor = [Drawing.Color]::SeaGreen
    $lblBuildItem.Text = T 'Click "Test the drive" to try it.' 'Clique em "Testar o pendrive" para experimentar.'
  } elseif ($st.state -eq 'error') {
    $lblBuild.Text = (T '✗ Build stopped with an error at {0}%: {1}' '✗ A montagem parou com erro em {0}%: {1}') -f $st.percent, $where; $lblBuild.ForeColor = [Drawing.Color]::Firebrick
    $lblBuildItem.Text = "$($st.item)   -   " + (T 'Click Build again to resume. Details: Open logs.' 'Clique em Montar de novo para continuar. Detalhes: Abrir registros.')
  } elseif ($age -gt 60) {
    $lblBuild.Text = (T 'Build paused at {0}% ({1}): its window was closed?' 'Montagem parada em {0}% ({1}): a janela foi fechada?') -f $st.percent, $where; $lblBuild.ForeColor = [Drawing.Color]::DarkOrange
    $lblBuildItem.Text = T 'Click Build again to continue where it stopped.' 'Clique em Montar de novo para continuar de onde parou.'
  } else {
    $script:building = $true
    $lblBuild.Text = (T 'Building {0}   {1}%  -  {2} of {3}  -  about {4} left' 'Montando {0}   {1}%  -  {2} de {3}  -  faltam cerca de {4}') -f $where, $st.percent, (Fmt $st.done), (Fmt $st.total), (Fmt-Time $st.secondsLeft)
    $lblBuild.ForeColor = [Drawing.Color]::Navy
    $lblBuildItem.Text = (T 'Now: {0}   ({1}/s)' 'Agora: {0}   ({1}/s)') -f $st.item, (Fmt $st.speed)
  }
}
$statusTimer = New-Ctl Timer @{ Interval = 1000 }
$statusTimer.Add_Tick({ try { Update-BuildStatus } catch { } })

# ---------------------------------------------------------------- actions

function Add-Area {
  $parts = $txtBox.Text.Replace(' ', '').Split(',')
  $nums = @($parts | ForEach-Object { $d = 0.0; if ([double]::TryParse($_, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $d } })
  if ($nums.Count -ne 4 -or $nums[0] -ge $nums[2] -or $nums[1] -ge $nums[3] -or [math]::Abs($nums[1]) -gt 85 -or [math]::Abs($nums[3]) -gt 85) {
    [void][Windows.Forms.MessageBox]::Show((T "Paste 4 numbers: minLon,minLat,maxLon,maxLat`nExample: -43.8,-23.1,-43.1,-22.7`n`nAt bboxfinder.com draw a box, then copy the 'Box' line." "Cole 4 números: minLon,minLat,maxLon,maxLat`nExemplo: -43.8,-23.1,-43.1,-22.7`n`nEm bboxfinder.com desenhe uma caixa e copie a linha 'Box'."), 'Survival Station')
    return
  }
  if (-not $script:catalog.planet -or -not (Test-Path "$($script:catalog.pmtiles)")) { Refresh-Catalog; return }
  $name = ($txtName.Text.ToLower() -replace '[^a-z0-9-]', '-').Trim('-')
  if (-not $name) { $name = 'custom' }
  $bbox = ($nums | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) }) -join ','
  $form.UseWaitCursor = $true; [Windows.Forms.Application]::DoEvents()
  $ErrorActionPreference = 'Continue'   # pmtiles logs on stderr
  $log = & $script:catalog.pmtiles extract $script:catalog.planet "$env:TEMP\dry.pmtiles" --maxzoom=15 "--bbox=$bbox" --dry-run 2>&1 | ForEach-Object { "$_" }
  $ErrorActionPreference = 'Stop'
  $form.UseWaitCursor = $false
  $size = if (($log -join ' ') -match 'archive size of ([\d.]+) (kB|MB|GB)') { [int64]([double]$Matches[1] * @{ kB = 1KB; MB = 1MB; GB = 1GB }[$Matches[2]]) } else { 0 }
  $item = [pscustomobject]@{ id = 'custom'; group = 'map'; name = "$name ($bbox)"; file = "portal/maps/$name.pmtiles"; size = $size; bbox = $bbox; mapName = $name }
  foreach ($n in @(Get-Leaves | Where-Object { $_.Tag.id -eq 'custom' })) { $n.Remove() }
  $n = $tree.Nodes['map'].Nodes.Add('custom', $item.name); $n.Tag = $item
  $script:updating = $true; $n.Checked = $true; $script:updating = $false
  Set-Label $n; Sync-Groups; Update-Summary
  $n.EnsureVisible()
}

function Format-Drive {
  $v = $script:drive
  if (-not $v -or $v.Folder) { return }
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $admin) {
    $a = [Windows.Forms.MessageBox]::Show((T 'Formatting needs administrator rights. Reopen this window as administrator?' 'Formatar precisa de administrador. Reabrir esta janela como administrador?'), 'Survival Station', 'YesNo', 'Question')
    if ($a -eq 'Yes') {
      try { Start-Process $PS -Verb RunAs -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath); $form.Close() } catch { }
    }
    return
  }
  $msg = (T "This ERASES EVERYTHING on {0}: ({1}, {2}).`n`nType the letter {0} to confirm:" "Isto APAGA TUDO em {0}: ({1}, {2}).`n`nDigite a letra {0} para confirmar:") -f $v.Letter, $v.Label, (Fmt $v.Size)
  if ([Microsoft.VisualBasic.Interaction]::InputBox($msg, 'Survival Station').Trim().ToUpper() -ne $v.Letter) { return }
  $form.UseWaitCursor = $true; [Windows.Forms.Application]::DoEvents()
  try {
    Format-Volume -DriveLetter $v.Letter -FileSystem exFAT -NewFileSystemLabel SURVIVAL -Force -Confirm:$false | Out-Null
    [void][Windows.Forms.MessageBox]::Show((T '{0}: is now exFAT.' '{0}: agora é exFAT.') -f $v.Letter, 'Survival Station')
  } catch {
    [void][Windows.Forms.MessageBox]::Show((T "Format failed. Close any windows using the drive and try again.`n`n{0}" "Falhou. Feche as janelas que usam o pendrive e tente de novo.`n`n{0}") -f $_.Exception.Message, 'Survival Station', 'OK', 'Error')
  } finally { $form.UseWaitCursor = $false }
  Load-Drives
}

function Stop-IfBuilding {
  if (-not $script:building) { return $false }
  [void][Windows.Forms.MessageBox]::Show((T 'A build is already running (see the blue bar). Wait for it to finish, or close its window first; then click again and it continues where it stopped.' 'Já tem uma montagem rodando (veja a barra azul). Espere terminar, ou feche a janela dela antes; depois clique de novo e ela continua de onde parou.'), 'Survival Station')
  $true
}

function Start-Build {
  if (Stop-IfBuilding) { return }
  $v = $script:drive
  if (-not $v) { [void][Windows.Forms.MessageBox]::Show((T 'Plug in the USB drive and choose it at the top.' 'Conecte o pendrive e escolha-o no alto.'), 'Survival Station'); return }
  $chosen = @(Get-Leaves | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
  if (-not @($chosen | Where-Object { $_.group -eq 'model' }) -and -not (Test-Path (Join-Path (Drive-Root) 'models\*.gguf'))) {
    [void][Windows.Forms.MessageBox]::Show((T 'Tick at least one AI model.' 'Marque pelo menos um modelo de IA.'), 'Survival Station'); return
  }
  if ($v.FileSystem -eq 'FAT32') {
    [void][Windows.Forms.MessageBox]::Show((T 'This drive is FAT32, which cannot hold files over 4 GB. Click "Format as exFAT" first.' 'Este pendrive é FAT32, que não aceita arquivos acima de 4 GB. Clique em "Formatar em exFAT" antes.'), 'Survival Station', 'OK', 'Warning'); return
  }
  $warn = ''
  if (-not $v.Folder -and $v.FileSystem -ne 'exFAT') { $warn += (T "{0} is {1}, not exFAT: Macs and phones may not be able to use it.`n`n" "{0} é {1}, não exFAT: Mac e celular podem não conseguir usar.`n`n") -f $v.Name, $v.FileSystem }
  if (-not $script:fits) { $warn += (T "It probably won't fit.`n`n" "Provavelmente não vai caber.`n`n") }
  $msg = $warn + ((T "Download {0} to {1} ?`n`nIt runs in a new window and can take hours. If the internet drops, click Build again: it continues where it stopped." "Baixar {0} para {1} ?`n`nRoda em outra janela e pode levar horas. Se a internet cair, clique em Montar de novo: ele continua de onde parou.") -f (Fmt $script:need), $v.Name)
  if ([Windows.Forms.MessageBox]::Show($msg, 'Survival Station', 'YesNo', 'Question') -ne 'Yes') { return }

  $ids = @($chosen | Where-Object { $_.id -ne 'custom' } | ForEach-Object { $_.id })
  if (-not $ids) { $ids = @('none') }
  $cmd = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Drive "{1}" -Items {2} -MapMaxZoom {3} -Staging {4} -Yes' -f $Builder, $v.Name, ($ids -join ','), (Zoom), (Staging)
  $custom = $chosen | Where-Object { $_.id -eq 'custom' } | Select-Object -First 1
  if ($custom) { $cmd += ' -MapBbox "{0}" -MapName {1}' -f $custom.bbox, $custom.mapName }
  Start-Process $PS -ArgumentList $cmd
  $lblStatus.Text = T 'Building in the other window. When it says Done, click "Test the drive".' 'Montando na outra janela. Quando aparecer Done, clique em "Testar o pendrive".'
}

# What on the selected kit has a newer version: library editions, AI engine, old maps, Survival-Data, app pages
function Get-Updates {
  $r = Drive-Root
  $c = $script:catalog
  $ups = @()
  foreach ($i in @($c.items | Where-Object { $_.group -eq 'zim' })) {
    $old = Old-Edition $i
    if ($old -and -not (On-Drive $i)) {
      $date = { param($n) if ($n -match '_(\d{4}-\d{2})\.zim$') { $Matches[1] } }
      $ups += [pscustomobject]@{ Text = '{0}: {1} -> {2}' -f $i.name, (& $date $old.Name), (& $date (Split-Path $i.file -Leaf)); Size = [double]$i.size }
    }
  }
  # books taken out of the kit (the update removes them)
  if ($c.retired) {
    foreach ($p in $c.retired.PSObject.Properties) {
      foreach ($f in (Get-ChildItem (Join-Path $r 'library') -Filter "$($p.Name)_*.zim" -ErrorAction SilentlyContinue)) {
        $ups += [pscustomobject]@{ Text = (T 'Remove {0}: {1}' 'Remover {0}: {1}') -f $f.Name, $p.Value; Size = 0 }
      }
    }
  }
  $ver = Join-Path $r 'engine\VERSION'
  if ($c.engine -and (Test-Path $ver) -and (Get-Content $ver) -ne $c.engine) {
    $ups += [pscustomobject]@{ Text = (T 'AI engine (llama.cpp): {0} -> {1}' 'Motor da IA (llama.cpp): {0} -> {1}') -f (Get-Content $ver), $c.engine; Size = 400MB }
  }
  foreach ($m in (Get-ChildItem (Join-Path $r 'portal\maps') -Filter *.pmtiles -ErrorAction SilentlyContinue)) {
    $months = [int](((Get-Date) - $m.LastWriteTime).TotalDays / 30.4)
    if ($months -ge 12) { $ups += [pscustomobject]@{ Text = (T 'Map {0}: {1} months old, re-cut from new map data' 'Mapa {0}: {1} meses, recortar dos dados novos') -f $m.BaseName, $months; Size = [double]$m.Length } }
  }
  $sd = Join-Path $r 'portal\survival-data'
  if ($c.sdPushed -and (Test-Path (Join-Path $sd 'index.html'))) {
    $stamp = Join-Path $sd '.version'
    $old = if (Test-Path $stamp) { (Get-Content $stamp) -ne $c.sdPushed } else { (Get-Item $sd).CreationTime -lt ([datetime]$c.sdPushed).AddDays(-2) }   # unpacked folders carry the last commit's date
    if ($old) { $ups += [pscustomobject]@{ Text = T 'Survival-Data: newer version' 'Survival-Data: versão mais nova'; Size = 1500MB } }
  }
  # the app itself (portal pages, start files, builder): newer in this project folder than on the kit
  $proj = Split-Path $PSScriptRoot
  if ($proj.TrimEnd('\') -ne $r.TrimEnd('\')) {
    $code = @(Get-ChildItem (Join-Path $proj 'portal') -File -Include *.html, *.js, *.css -Recurse -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\portal\\(vendor|maps|docs|survival-data)\\' }) +
            @(Get-ChildItem $proj -File -Include *.bat, *.command, *.sh -ErrorAction SilentlyContinue) + @(Get-ChildItem $PSScriptRoot -File)
    $newer = @($code | Where-Object { $t = Join-Path $r $_.FullName.Substring($proj.Length + 1); -not (Test-Path $t) -or $_.LastWriteTime -gt (Get-Item $t).LastWriteTime.AddSeconds(2) })
    $kitVersion = Get-AppVersion $r
    if (-not $kitVersion) { $kitVersion = T 'before 1.0.0' 'anterior à 1.0.0' }
    if ($newer) { $ups += [pscustomobject]@{ Text = (T 'App {0} -> {1}: {2} newer pages, start files and tools' 'App {0} -> {1}: {2} páginas, arquivos de início e ferramentas mais novos') -f $kitVersion, $AppVersion, $newer.Count; Size = 1MB } }
  }
  $ups
}

function Check-Updates {
  if (Stop-IfBuilding) { return }
  $r = Drive-Root
  if (-not $r -or -not (Test-Path (Join-Path $r 'START-WINDOWS.bat'))) {
    [void][Windows.Forms.MessageBox]::Show((T 'Choose a drive or folder that already has the kit.' 'Escolha um pendrive ou pasta que já tem o kit.'), 'Survival Station'); return
  }
  # compare against today's versions: refresh the list first if it is over a day old
  if (((Get-Date) - [datetime]$script:catalog.created).TotalDays -gt 1) { $script:afterCatalog = { Check-Updates }; Refresh-Catalog; return }
  $ups = @(Get-Updates)
  if (-not $ups) {
    [void][Windows.Forms.MessageBox]::Show(((T "Everything on {0} is up to date.`n(Compared with the versions online on {1}.)" "Tudo em {0} está atualizado.`n(Comparado com as versões online de {1}.)") -f $script:drive.Name, ([datetime]$script:catalog.created).ToString('g')), 'Survival Station')
    return
  }
  $total = ($ups | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum
  $msg = ((T "Updates for {0}:`n`n" "Atualizações para {0}:`n`n") -f $script:drive.Name) + (($ups | ForEach-Object { "  •  $($_.Text)" + $(if ($_.Size) { "   ($(Fmt $_.Size))" }) }) -join "`n") +
         ((T "`n`nAbout {0} to download. Update now?`n(New editions replace the old ones; nothing else changes.)" "`n`nCerca de {0} para baixar. Atualizar agora?`n(As edições novas substituem as antigas; nada mais muda.)") -f (Fmt $total))
  if ([Windows.Forms.MessageBox]::Show($msg, 'Survival Station', 'YesNo', 'Question') -ne 'Yes') { return }
  Start-Process $PS -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Drive "{1}" -Update -Staging {2} -Yes' -f $Builder, $script:drive.Name, (Staging))
  $lblStatus.Text = T 'Updating in the other window. When it says Done, click "Test the drive".' 'Atualizando na outra janela. Quando aparecer Done, clique em "Testar o pendrive".'
}

# write speed of the chosen drive, the same test the builder runs for "Automatic" (about 3 seconds)
function Test-SelectedDriveSpeed {
  $v = $script:drive
  if (-not $v) { return }
  if ($v.Folder -and $v.Letter -eq ([IO.Path]::GetFullPath($env:TEMP)).Substring(0, 1)) {
    $lblSpeed.Text = T 'A folder on this computer: files go straight there.' 'Uma pasta neste computador: os arquivos vão direto para ela.'; return
  }
  $form.UseWaitCursor = $true; $lblSpeed.Text = T 'Testing (about 3 seconds)...' 'Testando (cerca de 3 segundos)...'; [Windows.Forms.Application]::DoEvents()
  $f = Join-Path $v.Root 'survival-speed-test.tmp'
  try {
    $buf = New-Object byte[] (8MB); (New-Object Random).NextBytes($buf)
    $fs = New-Object IO.FileStream($f, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    $sw = [Diagnostics.Stopwatch]::StartNew(); $n = 0.0
    try { while ($sw.Elapsed.TotalSeconds -lt 3 -and $n -lt 1GB) { $fs.Write($buf, 0, $buf.Length); $n += $buf.Length }; $fs.Flush($true) } finally { $fs.Close(); $sw.Stop() }
    $mbps = $n / 1MB / [math]::Max(0.001, $sw.Elapsed.TotalSeconds)
    # one decimal on slow drives, so 1.5 MB/s doesn't read as 2
    $s = if ($mbps -lt 10) { $mbps.ToString('N1') } else { $mbps.ToString('N0') }
    $lblSpeed.Text = if ($mbps -ge 150) { (T '{0} MB/s: fast drive, everything goes straight to it.' '{0} MB/s: pendrive rápido, tudo vai direto para ele.') -f $s }
                     elseif ($mbps -ge 25) { (T '{0} MB/s: maps are prepared on this computer first.' '{0} MB/s: os mapas são preparados neste computador antes.') -f $s }
                     else { (T '{0} MB/s: slow drive, maps and downloads are prepared on this computer first.' '{0} MB/s: pendrive lento, mapas e downloads são preparados neste computador antes.') -f $s }
  } finally { Remove-Item $f -Force -ErrorAction SilentlyContinue; $form.UseWaitCursor = $false }
}

function Test-Drive {
  $r = Drive-Root
  if (-not $r -or -not (Test-Path (Join-Path $r 'START-WINDOWS.bat'))) {
    [void][Windows.Forms.MessageBox]::Show((T 'Survival Station is not there yet. Build it first.' 'O Survival Station ainda não está lá. Monte primeiro.'), 'Survival Station'); return
  }
  Start-Process (Join-Path $r 'START-WINDOWS.bat') -WorkingDirectory $r
}

# ---------------------------------------------------------------- events

# a greyed-out item (already included in a ticked bigger one) can't be ticked; say why.
# Ticking the bigger item is allowed: AfterCheck then unticks the smaller ones it includes.
$tree.Add_BeforeCheck({
  param($s, $e)
  if ($script:updating -or -not $e.Node.Tag -or $e.Node.Checked) { return }
  $b = Get-Blocker $e.Node.Tag
  if (-not $b -or $b.How -ne 'in') { return }
  $e.Cancel = $true
  $lblStatus.Text = (T '"{0}" is already included in "{1}", so it is not needed.' '"{0}" já está incluído em "{1}", então não é necessário.') -f $e.Node.Tag.name, $b.Node.Tag.name
})
$tree.Add_AfterCheck({
  param($s, $e)
  if ($script:updating) { return }
  Safe {
    $script:updating = $true
    if (-not $e.Node.Tag) { foreach ($c in $e.Node.Nodes) { $c.Checked = $e.Node.Checked } }
    $script:updating = $false
    # a bigger item (or a whole group) ticked: untick what it already includes, and say so
    $before = @(Get-Leaves | Where-Object Checked | ForEach-Object { $_.Tag.name })
    Resolve-Overlaps
    $dropped = @($before | Where-Object { $_ -notin @(Get-Leaves | Where-Object Checked | ForEach-Object { $_.Tag.name }) })
    if ($dropped -and $e.Node.Tag) {
      $lblStatus.Text = (T 'Unticked {0}: already included in "{1}".' 'Desmarcado {0}: já incluído em "{1}".') -f (($dropped | ForEach-Object { "`"$_`"" }) -join ', '), $e.Node.Tag.name
    }
    Relabel
    Sync-Groups
    Update-Summary
  }
})
$cbDrive.Add_SelectedIndexChanged({ Safe { Update-Drive } })
$cbZoom.Add_SelectedIndexChanged({ Safe { foreach ($n in (Get-Leaves)) { Set-Label $n }; Update-Summary } })
$btnDrives.Add_Click({ Safe { Load-Drives } })
$btnFormat.Add_Click({ Safe { Format-Drive } })
$btnFolder.Add_Click({ Safe { Choose-Folder } })
$btnLite.Add_Click({ Safe { Apply-Tier 'Lite' } })
$btnStd.Add_Click({ Safe { Apply-Tier 'Standard' } })
$btnFull.Add_Click({ Safe { Apply-Tier 'Full' } })
$chkEn.Add_Click({ Safe { if ($script:tier) { Apply-Tier $script:tier } } })
$chkPt.Add_Click({ Safe { if ($script:tier) { Apply-Tier $script:tier } } })
$btnNone.Add_Click({ Safe {
  $script:updating = $true; foreach ($n in (Get-Leaves)) { $n.Checked = $false }; $script:updating = $false
  $script:tier = $null; Sync-Groups; Update-Summary
} })
$btnArea.Add_Click({ Safe { Add-Area } })
$btnSizes.Add_Click({ Safe { Refresh-Catalog } })
$btnBuild.Add_Click({ Safe { Start-Build } })
$btnTest.Add_Click({ Safe { Test-Drive } })
$btnSpeed.Add_Click({ Safe { Test-SelectedDriveSpeed } })
$btnUpdates.Add_Click({ Safe { Check-Updates } })
# safe while a build runs: it reports files still downloading and only refreshes app files then
$btnVerify.Add_Click({ Safe {
  $r = Drive-Root
  if (-not $r -or -not (Test-Path (Join-Path $r 'START-WINDOWS.bat'))) {
    [void][Windows.Forms.MessageBox]::Show((T 'Choose a drive or folder that already has the kit.' 'Escolha um pendrive ou pasta que já tem o kit.'), 'Survival Station'); return
  }
  Start-Process $PS -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Drive "{1}" -Verify' -f $Builder, $script:drive.Name)
} })
$btnCopy.Add_Click({ Safe { Start-Process $PS -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $PSScriptRoot 'copy-kit.ps1')) } })
$btnLogs.Add_Click({ Safe { New-Item -ItemType Directory -Force $LogDir | Out-Null; Start-Process explorer.exe $LogDir } })

# opened from the "My kit" page: select that kit (a drive or a folder), then do what was asked
function Select-Kit($path) {
  $root = (Resolve-Path $path).Path.TrimEnd('\') + '\'
  $i = [array]::IndexOf(@($script:targets | ForEach-Object { $_.Root }), $root)
  if ($i -ge 0) { $cbDrive.SelectedIndex = $i; return }
  $script:folder = $root.TrimEnd('\')
  $script:drive = [pscustomobject]@{ Folder = $true; Name = $script:folder }
  Load-Drives
}
function Run-Action {
  if (-not $script:catalog) { $script:afterCatalog = { Run-Action }; return }   # sizes still loading
  switch ($Action) {
    'updates' { Check-Updates }
    'verify' { $btnVerify.PerformClick() }
    'add' { $lblStatus.Text = T 'Tick what you want to add, then click "Build the drive". Items already on the kit are marked "already there".' 'Marque o que quer adicionar e clique em "Montar o pendrive". O que já está no kit aparece como "já está lá".' }
  }
}

$form.Add_Shown({ Safe {
  # started from a console, Windows tends to open this window behind the others. TopMost/Activate alone
  # isn't always allowed; a quick minimize + restore always brings it to the front.
  $form.TopMost = $true
  $form.WindowState = 'Minimized'; $form.WindowState = 'Normal'
  $form.Activate(); $form.TopMost = $false
  Update-BuildStatus; $statusTimer.Start()
  Load-Drives
  if ($Kit) { Select-Kit $Kit }
  if (Test-Path $CacheFile) { Load-Catalog }
  # version 2 lists which items include others (and has the country maps cut along borders); 3 lists retired items
  if (-not $script:catalog -or $script:catalog.version -lt 4 -or ((Get-Date) - [datetime]$script:catalog.created).TotalDays -gt 7) { Refresh-Catalog }
  if ($Action) { Run-Action }
} })

[void]$form.ShowDialog()
