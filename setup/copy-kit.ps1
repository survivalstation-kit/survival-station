<#
.SYNOPSIS
  Copies a finished Survival Station kit to another USB drive or a folder on this computer.
  No internet needed: use it to share the kit. COPY-KIT.bat (on every kit) opens the window.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup\copy-kit.ps1
  powershell -ExecutionPolicy Bypass -File setup\copy-kit.ps1 -From E:\ -To F:\
  powershell -ExecutionPolicy Bypass -File setup\copy-kit.ps1 -From E:\ -To C:\Survival

  Run it again after an interruption: files already copied are skipped.
#>
param([string]$From = '', [string]$To = '', [switch]$Yes)

$ErrorActionPreference = 'Stop'
$Here = Split-Path $PSScriptRoot           # the kit (or project folder) this script sits in
$LogDir = Join-Path $Here 'logs'
$pt = (Get-UICulture).Name -like 'pt*'
function T($en, $ptText) { if ($pt) { $ptText } else { $en } }

function Fmt([double]$b) {
  if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -gt 0) { '{0:N0} MB' -f [math]::Max(1, $b / 1MB) } else { '0 MB' }
}
function Norm($p) { $p.TrimEnd('\') + '\' }
function Test-Kit($root) { (Test-Path (Join-Path $root 'START-WINDOWS.bat')) -and (Test-Path (Join-Path $root 'engine')) }
# work files that don't belong in a copy
function Skip-Rel($rel) { $rel -like '.download\*' -or $rel -like 'logs\*' -or $rel -like '*.part' }

# what has to be copied: total kit size, bytes still missing at the destination, biggest file (FAT32 limit)
function Get-CopyPlan($from, $to) {
  $have = @{}
  if (Test-Path $to) {
    foreach ($f in (Get-ChildItem -LiteralPath $to -Recurse -File -ErrorAction SilentlyContinue)) { $have[$f.FullName.Substring($to.Length)] = $f.Length }
  }
  $plan = @{ Total = 0.0; Need = 0.0; Largest = 0.0; Files = 0 }
  foreach ($f in (Get-ChildItem -LiteralPath $from -Recurse -File -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($from.Length)
    if (Skip-Rel $rel) { continue }
    $plan.Files++
    $plan.Total += $f.Length
    if ($have[$rel] -ne $f.Length) { $plan.Need += $f.Length }
    if ($f.Length -gt $plan.Largest) { $plan.Largest = $f.Length }
  }
  $plan
}

function Get-Volume-Of($path) { Get-Volume -DriveLetter $path[0] -ErrorAction SilentlyContinue }

# problems that stop the copy, or $null
function Test-Copy($from, $to, $plan) {
  if (-not (Test-Kit $from)) { return (T "$from has no Survival Station kit." "$from não tem o kit Survival Station.") }
  if ($to.StartsWith($from, 'OrdinalIgnoreCase') -or $from.StartsWith($to, 'OrdinalIgnoreCase')) { return (T 'Copy to a different drive or folder.' 'Copie para outra unidade ou pasta.') }
  $v = Get-Volume-Of $to
  if (-not $v) { return (T "Drive $($to.Substring(0, 2)) not found." "Unidade $($to.Substring(0, 2)) não encontrada.") }
  if ($v.FileSystem -eq 'FAT32' -and $plan.Largest -ge 4GB) {
    return (T "$($to.Substring(0, 2)) is FAT32, which can't hold files over 4 GB (the AI models, big libraries). Format it as exFAT first." "$($to.Substring(0, 2)) é FAT32, que não aceita arquivos acima de 4 GB (modelos de IA, bibliotecas grandes). Formate em exFAT antes.")
  }
  if ($plan.Need -gt $v.SizeRemaining) {
    return ((T 'Not enough space: needs {0}, {1} has {2} free.' 'Não cabe: precisa de {0}, {1} tem {2} livres.') -f (Fmt $plan.Need), $to.Substring(0, 2), (Fmt $v.SizeRemaining))
  }
  $null
}

function Copy-Kit($from, $to) {
  New-Item -ItemType Directory -Force $to, $LogDir | Out-Null
  $log = Join-Path $LogDir ('copy-{0:yyyy-MM-dd_HHmmss}.log' -f (Get-Date))
  Write-Host ("`n" + (T 'Copying {0} -> {1}' 'Copiando {0} -> {1}') -f $from, $to) -ForegroundColor Cyan
  # "X:\." because robocopy reads a quoted trailing backslash as an escaped quote
  & "$env:SystemRoot\System32\robocopy.exe" "$($from.TrimEnd('\'))\." "$($to.TrimEnd('\'))\." /E /J /R:2 /W:5 /NDL `
    /XD "$($from).download" "$($from)logs" /XF '*.part' /TEE "/LOG:$log"
  if ($LASTEXITCODE -ge 8) {   # robocopy: 0-7 = success, 8+ = some files failed
    Write-Host ("`n" + (T 'Some files could not be copied (see above). Run it again to retry; copied files are skipped.' 'Alguns arquivos não foram copiados (veja acima). Rode de novo; os já copiados são pulados.')) -ForegroundColor Red
    Write-Host "   Log: $log" -ForegroundColor Red
    exit 1
  }
  if ($to.Length -gt 3) {
    # a folder on this computer: add a desktop shortcut, like the builder does
    try {
      $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Survival Station.lnk'))
      $lnk.TargetPath = Join-Path $to 'START-WINDOWS.bat'
      $lnk.WorkingDirectory = $to
      $lnk.IconLocation = "$env:SystemRoot\System32\shell32.dll,23"
      $lnk.Save()
    } catch { }
  }
  Write-Host ("`n" + (T 'Done. Test the copy: run {0}START-WINDOWS.bat' 'Pronto. Teste a cópia: rode {0}START-WINDOWS.bat') -f $to) -ForegroundColor Green
  Write-Host "   Log: $log"
}

# ---------------------------------------------------------------- command line

if ($From -and $To) {
  $From = Norm (Resolve-Path $From).Path
  $To = Norm ([IO.Path]::GetFullPath($To))
  Write-Host (T 'Checking what to copy...' 'Conferindo o que copiar...')
  $plan = Get-CopyPlan $From $To
  "   {0} files, {1}; {2} still to copy" -f $plan.Files, (Fmt $plan.Total), (Fmt $plan.Need)
  $problem = Test-Copy $From $To $plan
  if ($problem) { Write-Host "`n$problem" -ForegroundColor Red; exit 1 }
  if (-not $Yes -and (Read-Host ("`n" + (T 'Copy? [y/N]' 'Copiar? [s/N]'))) -notmatch '^[ys]') { exit }
  Copy-Kit $From $To
  exit
}

# ---------------------------------------------------------------- window

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic
[Windows.Forms.Application]::EnableVisualStyles()
$PS = Join-Path $PSHOME 'powershell.exe'

function New-Ctl($type, [hashtable]$props = @{}) {
  $c = New-Object "Windows.Forms.$type"
  foreach ($k in $props.Keys) { $c.$k = $props[$k] }
  $c
}
function New-Row { New-Ctl FlowLayoutPanel @{ Dock = 'Top'; AutoSize = $true; Padding = (New-Object Windows.Forms.Padding 4, 6, 4, 0) } }
function New-Label($text, $w = 110) { New-Ctl Label @{ Text = $text; Width = $w; Margin = (New-Object Windows.Forms.Padding 3, 7, 3, 0) } }
function Show-Msg($text, $icon = 'Information') { [void][Windows.Forms.MessageBox]::Show($text, 'Survival Station', 'OK', $icon) }

$form = New-Ctl Form @{
  Text = 'Survival Station - ' + (T 'copy the kit' 'copiar o kit'); Font = New-Object Drawing.Font('Segoe UI', 10); AutoScaleMode = 'Dpi'
  Size = New-Object Drawing.Size(1000, 400); MinimumSize = New-Object Drawing.Size(640, 400); StartPosition = 'CenterScreen'
}
$intro = New-Ctl Label @{ Dock = 'Top'; Height = 48; Padding = (New-Object Windows.Forms.Padding 8, 8, 8, 0)
  Text = (T 'Copies a finished kit to another USB drive or computer. No internet needed - use it to share.' 'Copia um kit pronto para outro pendrive ou computador. Não precisa de internet - use para compartilhar.') }

$rowFrom = New-Row
$cbFrom = New-Ctl ComboBox @{ DropDownStyle = 'DropDownList'; Width = 480 }
$btnFromFolder = New-Ctl Button @{ Text = (T 'Folder...' 'Pasta...'); AutoSize = $true }
$rowFrom.Controls.AddRange(@((New-Label (T 'Copy from:' 'Copiar de:')), $cbFrom, $btnFromFolder))

$rowTo = New-Row
$cbTo = New-Ctl ComboBox @{ DropDownStyle = 'DropDownList'; Width = 480 }
$btnToFolder = New-Ctl Button @{ Text = (T 'Folder...' 'Pasta...'); AutoSize = $true }
$btnRefresh = New-Ctl Button @{ Text = (T 'Refresh' 'Atualizar'); AutoSize = $true }
$btnFormat = New-Ctl Button @{ Text = (T 'Format as exFAT...' 'Formatar em exFAT...'); AutoSize = $true }
$rowTo.Controls.AddRange(@((New-Label (T 'Copy to:' 'Copiar para:')), $cbTo, $btnToFolder, $btnRefresh, $btnFormat))

$bottom = New-Ctl TableLayoutPanel @{ Dock = 'Fill'; ColumnCount = 1; Padding = (New-Object Windows.Forms.Padding 8) }
[void]$bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle 'Percent', 100))
$lblSize = New-Ctl Label @{ AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold) }
$lblFit = New-Ctl Label @{ AutoSize = $true; MaximumSize = New-Object Drawing.Size(800, 0) }
$bar = New-Ctl ProgressBar @{ Dock = 'Fill'; Height = 18 }
$buttons = New-Ctl FlowLayoutPanel @{ Dock = 'Fill'; AutoSize = $true; FlowDirection = 'RightToLeft' }
$btnCopy = New-Ctl Button @{ Text = (T 'Copy' 'Copiar'); AutoSize = $true; Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold) }
$buttons.Controls.Add($btnCopy)
foreach ($c in $lblSize, $lblFit, $bar, $buttons) { [void]$bottom.Controls.Add($c) }
$form.Controls.AddRange(@($bottom, $rowTo, $rowFrom, $intro))

$script:froms = @(); $script:tos = @(); $script:plan = $null
$script:toFolder = Join-Path $env:SystemDrive 'Survival'

function Load-Lists([string]$keepFrom, [string]$keepTo) {
  $vols = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -and $_.DriveType -in 'Removable', 'Fixed' } | Sort-Object DriveLetter)
  # sources: this kit, kits on any drive, the usual local folder
  $script:froms = @()
  foreach ($p in @($Here) + @($vols | ForEach-Object { "$($_.DriveLetter):\" }) + @($script:toFolder) + @($keepFrom)) {
    if ($p -and (Test-Kit $p) -and -not ($script:froms -contains (Norm $p))) { $script:froms += Norm $p }
  }
  $cbFrom.Items.Clear()
  foreach ($p in $script:froms) { [void]$cbFrom.Items.Add($(if ($p -eq (Norm $Here)) { $p + '   ' + (T '(this kit)' '(este kit)') } else { $p })) }
  if (-not $script:froms) { [void]$cbFrom.Items.Add((T '(no kit found - plug in the USB drive with the kit)' '(nenhum kit - conecte o pendrive com o kit)')) }
  $i = [array]::IndexOf($script:froms, $keepFrom); $cbFrom.SelectedIndex = [math]::Max(0, $i)

  # destinations: other drives (not the system disk), plus a folder on this computer
  $script:tos = @()
  $cbTo.Items.Clear()
  foreach ($v in ($vols | Where-Object { "$($_.DriveLetter):" -ne $env:SystemDrive })) {
    $script:tos += [pscustomobject]@{ Root = "$($v.DriveLetter):\"; Letter = "$($v.DriveLetter)"; Folder = $false; Label = $v.FileSystemLabel; Size = $v.Size }
    [void]$cbTo.Items.Add(('{0}:  {1}  -  {2}  -  {3} {4} / {5}' -f $v.DriveLetter, $v.FileSystemLabel, $v.FileSystem, (Fmt $v.SizeRemaining), (T 'free' 'livre'), (Fmt $v.Size)))
  }
  $script:tos += [pscustomobject]@{ Root = Norm $script:toFolder; Letter = "$($script:toFolder[0])"; Folder = $true }
  [void]$cbTo.Items.Add(((T 'This computer, folder {0}' 'Este computador, pasta {0}') -f $script:toFolder))
  $pick = -1
  for ($i = 0; $i -lt $script:tos.Count; $i++) {
    $t = $script:tos[$i]
    if ($t.Root -eq $keepTo) { $pick = $i }
    elseif (-not $keepTo -and $pick -lt 0 -and $script:froms.Count -and $t.Root -ne $script:froms[$cbFrom.SelectedIndex] -and -not $t.Folder) { $pick = $i }
  }
  $cbTo.SelectedIndex = [math]::Max(0, $pick)
  Update-Plan
}

function Selected-From { if ($script:froms.Count -and $cbFrom.SelectedIndex -ge 0) { $script:froms[$cbFrom.SelectedIndex] } }
function Selected-To { if ($cbTo.SelectedIndex -ge 0) { $script:tos[$cbTo.SelectedIndex] } }

function Update-Plan {
  $from = Selected-From; $to = Selected-To
  $btnFormat.Enabled = $to -and -not $to.Folder
  $script:plan = $null; $script:problem = $null
  if (-not $from -or -not $to) { $lblSize.Text = ''; $lblFit.Text = ''; $bar.Value = 0; $btnCopy.Enabled = $false; return }
  $form.UseWaitCursor = $true; $lblSize.Text = T 'Checking...' 'Conferindo...'; [Windows.Forms.Application]::DoEvents()
  try { $script:plan = Get-CopyPlan $from $to.Root } finally { $form.UseWaitCursor = $false }
  $script:problem = Test-Copy $from $to.Root $script:plan
  $free = [double](Get-Volume-Of $to.Root).SizeRemaining
  $lblSize.Text = (T 'Kit: {0} ({1} files)  -  {2} to copy' 'Kit: {0} ({1} arquivos)  -  {2} para copiar') -f (Fmt $script:plan.Total), $script:plan.Files, (Fmt $script:plan.Need)
  $bar.Value = [int][math]::Min(100.0, [math]::Round(100.0 * $script:plan.Need / [math]::Max(1.0, $free)))
  if ($script:problem) { $lblFit.Text = '✗ ' + $script:problem; $lblFit.ForeColor = [Drawing.Color]::Firebrick }
  else { $lblFit.Text = (T '✓ Fits: {0} free, {1} left over' '✓ Cabe: {0} livres, sobram {1}') -f (Fmt $free), (Fmt ($free - $script:plan.Need)); $lblFit.ForeColor = [Drawing.Color]::SeaGreen }
  $btnCopy.Enabled = -not $script:problem
}

function Pick-Folder($desc, $start) {
  $dlg = New-Ctl FolderBrowserDialog @{ Description = $desc; ShowNewFolderButton = $true; SelectedPath = $start }
  if ($dlg.ShowDialog($form) -eq 'OK') { $dlg.SelectedPath }
}

function Format-Target {
  $t = Selected-To
  if (-not $t -or $t.Folder) { return }
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $admin) {
    if ([Windows.Forms.MessageBox]::Show((T 'Formatting needs administrator rights. Reopen this window as administrator?' 'Formatar precisa de administrador. Reabrir esta janela como administrador?'), 'Survival Station', 'YesNo', 'Question') -eq 'Yes') {
      try { Start-Process $PS -Verb RunAs -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath); $form.Close() } catch { }
    }
    return
  }
  $msg = (T "This ERASES EVERYTHING on {0}: ({1}, {2}).`n`nType the letter {0} to confirm:" "Isto APAGA TUDO em {0}: ({1}, {2}).`n`nDigite a letra {0} para confirmar:") -f $t.Letter, $t.Label, (Fmt $t.Size)
  if ([Microsoft.VisualBasic.Interaction]::InputBox($msg, 'Survival Station').Trim().ToUpper() -ne $t.Letter) { return }
  $form.UseWaitCursor = $true
  try { Format-Volume -DriveLetter $t.Letter -FileSystem exFAT -NewFileSystemLabel SURVIVAL -Force -Confirm:$false | Out-Null }
  catch { Show-Msg ((T "Format failed. Close any windows using the drive and try again.`n`n{0}" "Falhou. Feche as janelas que usam o pendrive e tente de novo.`n`n{0}") -f $_.Exception.Message) 'Error' }
  finally { $form.UseWaitCursor = $false }
  Load-Lists (Selected-From) $t.Root
}

function Start-Copy {
  $from = Selected-From; $to = Selected-To
  Update-Plan
  if ($script:problem -or -not $script:plan) { return }
  $msg = (T "Copy {0} from {1} to {2} ?`n`nIt runs in a new window. If it stops, click Copy again: files already copied are skipped." "Copiar {0} de {1} para {2} ?`n`nRoda em outra janela. Se parar, clique em Copiar de novo: os arquivos já copiados são pulados.") -f (Fmt $script:plan.Need), $from, $to.Root
  if ([Windows.Forms.MessageBox]::Show($msg, 'Survival Station', 'YesNo', 'Question') -ne 'Yes') { return }
  # "X:\." keeps a trailing backslash from escaping the closing quote
  Start-Process $PS -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -From "{1}." -To "{2}." -Yes' -f $PSCommandPath, $from, $to.Root)
}

function Safe([scriptblock]$block) {
  try { & $block } catch {
    New-Item -ItemType Directory -Force $LogDir -ErrorAction SilentlyContinue | Out-Null
    Add-Content -Encoding UTF8 (Join-Path $LogDir 'copy-window.log') "$((Get-Date).ToString('s'))  $($_.Exception.Message)" -ErrorAction SilentlyContinue
    Show-Msg $_.Exception.Message 'Error'
  }
}

$cbFrom.Add_SelectionChangeCommitted({ Safe { Update-Plan } })
$cbTo.Add_SelectionChangeCommitted({ Safe { Update-Plan } })
$btnRefresh.Add_Click({ Safe { Load-Lists (Selected-From) (Selected-To).Root } })
$btnFormat.Add_Click({ Safe { Format-Target } })
$btnCopy.Add_Click({ Safe { Start-Copy } })
$btnFromFolder.Add_Click({ Safe {
  $p = Pick-Folder (T 'Folder that has the kit (START-WINDOWS.bat inside)' 'Pasta que tem o kit (com START-WINDOWS.bat)') $script:toFolder
  if (-not $p) { return }
  if (-not (Test-Kit $p)) { Show-Msg (T 'That folder has no Survival Station kit.' 'Essa pasta não tem o kit Survival Station.') 'Warning'; return }
  Load-Lists (Norm $p) (Selected-To).Root
} })
$btnToFolder.Add_Click({ Safe {
  $p = Pick-Folder (T 'Folder for the copy (a new "Survival" folder is fine)' 'Pasta para a cópia (uma pasta nova "Survival" serve)') (Split-Path $script:toFolder)
  if (-not $p) { return }
  if ($p.TrimEnd('\').Length -le 2) { $p = Join-Path $p 'Survival' }
  $script:toFolder = $p.TrimEnd('\')
  Load-Lists (Selected-From) (Norm $script:toFolder)
} })
$form.Add_Shown({ Safe { Load-Lists } })
[void]$form.ShowDialog()
