<#
.SYNOPSIS
  Started hidden by START-WINDOWS.bat. Waits for the start window to close, however it closes (a key pressed,
  or its X clicked), then closes the kit's servers, so none keep running with no window to stop them.
#>
$ErrorActionPreference = 'SilentlyContinue'
$start = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId   # the start window
if (-not $start) { exit 0 }
try { Wait-Process -Id $start } catch { }
& (Join-Path $PSScriptRoot 'stop-old-kit.ps1') -Quiet
