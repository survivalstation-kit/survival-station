<#
.SYNOPSIS
  Closes a running Survival Station: its servers, its helper, its watcher and its start window.
  - Run by START-WINDOWS.bat first: closes a kit that is still running (an earlier start that was never shut
    down, or one started from another copy of the kit), so the new one gets its ports and the computer isn't
    running two AIs.
  - Run by setup\watch-kit.ps1 when the start window is closed with its X, and by the home page's
    "Shut down the kit" button (through setup\kit-control.ps1), with -Quiet.

  Only the kit's own programs: the map tool only while serving maps (a build cutting a map keeps running),
  Caddy only with the kit's settings.
#>
param([switch]$Quiet)
$me = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId   # whoever runs us: never closed
$all = @(Get-CimInstance Win32_Process | Where-Object {
  $cmd = "$($_.CommandLine)"
  $_.ProcessId -ne $PID -and $_.ProcessId -ne $me -and (
    ($_.Name -in 'llama-server.exe', 'kiwix-serve.exe', 'whisper-server.exe') -or
    ($_.Name -eq 'pmtiles.exe' -and $cmd -match '\sserve\s') -or
    ($_.Name -eq 'caddy.exe' -and $cmd -match 'survival-Caddyfile') -or
    ($_.Name -eq 'powershell.exe' -and $cmd -match '(kit-control|watch-kit|share-server)\.ps1') -or
    ($_.Name -eq 'cmd.exe' -and $cmd -match 'START-WINDOWS\.bat'))
})
if (-not $all) { return }
# old watchers first: otherwise closing their start window would make them close the kit starting now
$watchers = @($all | Where-Object { "$($_.CommandLine)" -match 'watch-kit\.ps1' })
foreach ($p in $watchers + @($all | Where-Object { $watchers -notcontains $_ })) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
if ($Quiet) { return }
Start-Sleep -Seconds 1   # let Windows free their ports
$what = ($all | Where-Object { "$($_.CommandLine)" -notmatch 'watch-kit\.ps1' } | ForEach-Object { $_.Name -replace '\.exe$', '' } | Sort-Object -Unique) -join ', '
if (-not $what) { return }
Write-Host " An earlier Survival Station was still running: closed it ($what)."
Write-Host " Um Survival Station anterior ainda estava rodando: foi fechado."
Write-Host ''
