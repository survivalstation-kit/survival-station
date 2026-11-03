<#
.SYNOPSIS
  Run by START-WINDOWS.bat first: closes a Survival Station that is still running (an earlier start that was
  never shut down, or one started from another copy of the kit), so the new one gets its ports and the
  computer isn't running two AIs. Closes the kit's servers, its helper and its old start window.

  Only the kit's own programs: the map tool only while serving maps (a build cutting a map keeps running),
  Caddy only with the kit's settings.
#>
$me = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId   # the start window running us
$old = @(Get-CimInstance Win32_Process | Where-Object {
  $cmd = "$($_.CommandLine)"
  ($_.Name -in 'llama-server.exe', 'kiwix-serve.exe', 'whisper-server.exe') -or
  ($_.Name -eq 'pmtiles.exe' -and $cmd -match '\sserve\s') -or
  ($_.Name -eq 'caddy.exe' -and $cmd -match 'survival-Caddyfile') -or
  ($_.Name -eq 'powershell.exe' -and $cmd -match 'kit-control\.ps1') -or
  ($_.Name -eq 'cmd.exe' -and $cmd -match 'START-WINDOWS\.bat' -and $_.ProcessId -ne $me)
})
if (-not $old) { return }
foreach ($p in $old) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1   # let Windows free their ports
$what = ($old | ForEach-Object { $_.Name -replace '\.exe$', '' } | Sort-Object -Unique) -join ', '
Write-Host " An earlier Survival Station was still running: closed it ($what)."
Write-Host " Um Survival Station anterior ainda estava rodando: foi fechado."
Write-Host ''
