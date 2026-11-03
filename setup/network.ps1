<#
.SYNOPSIS
  Run by START-WINDOWS.bat once the AI is up. Writes portal\kit-address.json (this computer's network
  addresses, for the home page's QR code) and, when the kit has Caddy (the Voice extra), the settings for its
  secure address: https on port 8443, so phones may use the microphone (browsers only allow it on https).

  Caddy makes its own certificate authority, kept on the kit (tools\caddy-data), and a certificate for each
  address; phones show a one-time warning because no phone knows that authority. Behind it:
    /library/*  -> the library (kiwix-serve, started with --urlRootLocation /library)
    /tiles/*    -> the map server for maps over 2 GB
    /voice/*    -> speech to text (whisper-server, which listens on this computer only)
    everything else -> the AI server, which also serves the portal pages
#>
param([string]$Kit, [int]$Port = 8080, [int]$LibPort = 8090, [int]$MapPort = 8092, [int]$VoicePort = 8093, [int]$HttpsPort = 8443,
      [string]$Caddyfile = (Join-Path $env:TEMP 'survival-Caddyfile'))

$Kit = (Resolve-Path $Kit).Path.TrimEnd('\')
# addresses with a gateway (a phone hotspot, a router) first: those are the ones phones can reach
$c = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Address })
$ips = @($c | Sort-Object { -not $_.IPv4DefaultGateway } | ForEach-Object { $_.IPv4Address.IPAddress } |
  Where-Object { $_ -notlike '127.*' -and $_ -notlike '169.254.*' } | Select-Object -Unique)

$address = [ordered]@{ port = $Port; ips = $ips }
if (Test-Path (Join-Path $Kit 'tools\win\caddy\caddy.exe')) {
  $address.https = $HttpsPort
  $sites = (@('localhost') + $ips | ForEach-Object { "https://$($_):$HttpsPort" }) -join ', '
  $data = (Join-Path $Kit 'tools\caddy-data').Replace('\', '/')
  # phones opening https://<ip> send no server name (SNI), so Caddy needs to be told which certificate to show:
  # the first address, the one phones on the hotspot use
  $sni = if ($ips) { $ips[0] } else { 'localhost' }
  [IO.File]::WriteAllText($Caddyfile, @"
{
	admin off
	local_certs
	skip_install_trust
	auto_https disable_redirects
	default_sni $sni
	storage file_system "$data"
}
$sites {
	tls internal
	handle /library* {
		reverse_proxy 127.0.0.1:$LibPort
	}
	handle_path /tiles/* {
		reverse_proxy 127.0.0.1:$MapPort
	}
	handle_path /voice/* {
		reverse_proxy 127.0.0.1:$VoicePort
	}
	handle {
		reverse_proxy 127.0.0.1:$Port
	}
}
"@)
}
[IO.File]::WriteAllText((Join-Path $Kit 'portal\kit-address.json'), (ConvertTo-Json -Compress -InputObject $address))
