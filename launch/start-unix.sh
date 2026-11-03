#!/usr/bin/env bash
# Survival Station launcher for macOS and Linux (called by START-MAC.command / START-LINUX.sh)
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
PORT=8080
LIBPORT=8090

echo
echo " =============================================="
echo "   SURVIVAL STATION  -  offline AI + library"
echo "                        IA offline + biblioteca"
echo " =============================================="
echo

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)          OS=mac-arm64 ;;
  Darwin-x86_64)         OS=mac-x64 ;;
  Linux-x86_64)          OS=linux-x64 ;;
  Linux-aarch64|Linux-arm64) OS=linux-arm64 ;;
  *) OS=unknown ;;
esac

open_url() { if command -v open >/dev/null; then open "$1"; else xdg-open "$1" >/dev/null 2>&1 & fi; }

# USB drives are sometimes mounted "noexec" (Linux) or flagged by Gatekeeper (macOS).
# If a program won't run from the drive, run a copy from the computer's temp folder instead.
runnable_dir() {   # $1 = folder on drive, $2 = program name -> prints folder to run from
  local dir="$1" exe="$2"
  [ -f "$dir/$exe" ] || return 1
  chmod +x "$dir"/* 2>/dev/null
  [ "$(uname -s)" = Darwin ] && xattr -dr com.apple.quarantine "$dir" 2>/dev/null
  if "$dir/$exe" --version >/dev/null 2>&1; then echo "$dir"; return 0; fi
  local copy="${TMPDIR:-/tmp}/survival-$(basename "$(dirname "$dir")")-$(basename "$dir")"
  rm -rf "$copy" && cp -R "$dir" "$copy" && chmod +x "$copy"/* 2>/dev/null
  [ "$(uname -s)" = Darwin ] && xattr -dr com.apple.quarantine "$copy" 2>/dev/null
  "$copy/$exe" --version >/dev/null 2>&1 && { echo "$copy"; return 0; }
  return 1
}

PIDS=()
cleanup() { echo; echo " Shutting down..."; kill "${PIDS[@]}" 2>/dev/null; exit 0; }
trap cleanup INT TERM

# ---- library server
shopt -s nullglob
ZIMS=("$ROOT"/library/*.zim)
if [ ${#ZIMS[@]} -gt 0 ] && KIWIX=$(runnable_dir "$ROOT/kiwix/$OS" kiwix-serve); then
  # kiwix-serve names each book after the path it was given: run it inside library/ with bare
  # file names, otherwise article links break
  # under /library, so the secure address (Caddy, below) can pass /library on to it
  (cd "$ROOT/library" && exec "$KIWIX/kiwix-serve" --port "$LIBPORT" --urlRootLocation /library "${ZIMS[@]##*/}") >"${TMPDIR:-/tmp}/survival-kiwix.log" 2>&1 &
  PIDS+=($!)
  echo " Library: ${#ZIMS[@]} archive(s) on port $LIBPORT"
else
  echo " Library server not started (no .zim files, or no kiwix build for $OS)."
fi

# ---- voice: speech to text for the chat (whisper.cpp builds exist for Linux, not Mac), this computer only
WMODELS=("$ROOT"/models/whisper/*.bin)
WDIR="$ROOT/tools/$OS/whisper"
if [ ${#WMODELS[@]} -gt 0 ] && [ -f "$WDIR/whisper-server" ]; then
  chmod +x "$WDIR/whisper-server" 2>/dev/null
  if ! [ -x "$WDIR/whisper-server" ]; then   # drive mounted noexec: run a copy
    rm -rf "${TMPDIR:-/tmp}/survival-whisper" && cp -R "$WDIR" "${TMPDIR:-/tmp}/survival-whisper" && WDIR="${TMPDIR:-/tmp}/survival-whisper" && chmod +x "$WDIR/whisper-server"
  fi
  LD_LIBRARY_PATH="$WDIR:$LD_LIBRARY_PATH" "$WDIR/whisper-server" -m "${WMODELS[0]}" --host 127.0.0.1 --port 8093 >"${TMPDIR:-/tmp}/survival-voice.log" 2>&1 &
  PIDS+=($!)
fi

# ---- AI server
MODELS=("$ROOT"/models/*.gguf)
if [ ${#MODELS[@]} -eq 0 ] || ! ENGINE=$(runnable_dir "$ROOT/engine/$OS" llama-server); then
  echo " No AI engine/model for $OS - opening the offline pages only."
  open_url "$ROOT/portal/index.html"
  [ ${#PIDS[@]} -gt 0 ] && { echo " Press Ctrl+C to stop the library."; wait; }
  exit 0
fi

DEF=1
for i in "${!MODELS[@]}"; do
  name=$(basename "${MODELS[$i]}" .gguf)
  # a model with a vision part in models/mmproj/ can look at photos
  if [ -f "$ROOT/models/mmproj/$(basename "${MODELS[$i]}")" ]; then echo "   $((i + 1)). $name   [photos / fotos]"; else echo "   $((i + 1)). $name"; fi
  case "$name" in *Qwen3-4B*) DEF=$((i + 1)) ;; esac
done
# on battery, the smallest model is the default: it uses far less power
ONBATTERY=
if [ "$(uname -s)" = Darwin ]; then pmset -g batt 2>/dev/null | grep -q "'Battery Power'" && ONBATTERY=1
else grep -qs Discharging /sys/class/power_supply/BAT*/status && ONBATTERY=1; fi
if [ -n "$ONBATTERY" ]; then
  for i in "${!MODELS[@]}"; do case "$(basename "${MODELS[$i]}")" in *Llama-3.2-1B*) DEF=$((i + 1)) ;; esac; done
fi
PICK=$DEF
if [ ${#MODELS[@]} -gt 1 ]; then
  echo
  [ -n "$ONBATTERY" ] && echo " On battery: the smallest model is picked to save power.  /  Na bateria: o menor modelo foi escolhido para economizar."
  echo " Old or slow computer? Pick Llama-3.2-1B.  /  Computador antigo ou lento? Escolha Llama-3.2-1B."
  read -r -t 10 -p "  Choose AI model / Modelo de IA [1-${#MODELS[@]}] (default $DEF): " PICK
  [[ "$PICK" =~ ^[0-9]+$ ]] && [ "$PICK" -ge 1 ] && [ "$PICK" -le ${#MODELS[@]} ] || PICK=$DEF
  echo
fi
MODEL="${MODELS[$((PICK - 1))]}"
echo " Starting AI with $(basename "$MODEL") ..."

export LD_LIBRARY_PATH="$ENGINE:$LD_LIBRARY_PATH" DYLD_LIBRARY_PATH="$ENGINE:$DYLD_LIBRARY_PATH"
VISION=()
MM="$ROOT/models/mmproj/$(basename "$MODEL")"
[ -f "$MM" ] && VISION=(--mmproj "$MM")
"$ENGINE/llama-server" -m "$MODEL" "${VISION[@]}" --host 0.0.0.0 --port "$PORT" --path "$ROOT/portal" -c 8192 \
  >"${TMPDIR:-/tmp}/survival-ai.log" 2>&1 &
AI_PID=$!
PIDS+=($AI_PID)

echo " Waiting for the AI to load ... / Carregando a IA, pode levar um minuto..."
for _ in $(seq 180); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" && break
  kill -0 "$AI_PID" 2>/dev/null || { echo " AI failed to start. Log: ${TMPDIR:-/tmp}/survival-ai.log"; tail -5 "${TMPDIR:-/tmp}/survival-ai.log"; break; }
  sleep 1
done

# this computer's network addresses for the home page's QR code
if [ "$(uname -s)" = Darwin ]; then
  IPS=$(for ifc in en0 en1 bridge100; do ipconfig getifaddr "$ifc" 2>/dev/null; done)
else
  IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v ':' | grep -v '^127\.')
fi
# secure address https://...:8443 (Caddy, with the Voice extra on Linux) so phones may use the microphone;
# same settings as setup/network.ps1 on Windows
HTTPSPORT=
CADDY="$ROOT/tools/$OS/caddy/caddy"
if [ -f "$CADDY" ] && [ -f "$ROOT/tools/$OS/whisper/whisper-server" ]; then
  chmod +x "$CADDY" 2>/dev/null
  if ! [ -x "$CADDY" ]; then cp "$CADDY" "${TMPDIR:-/tmp}/survival-caddy" && CADDY="${TMPDIR:-/tmp}/survival-caddy" && chmod +x "$CADDY"; fi
  HTTPSPORT=8443
  SNI=$(echo $IPS | awk '{print $1}'); [ -n "$SNI" ] || SNI=localhost
  SITES="https://localhost:$HTTPSPORT"; for ip in $IPS; do SITES="$SITES, https://$ip:$HTTPSPORT"; done
  CADDYFILE="${TMPDIR:-/tmp}/survival-Caddyfile"
  cat >"$CADDYFILE" <<EOF
{
	admin off
	local_certs
	skip_install_trust
	auto_https disable_redirects
	default_sni $SNI
	storage file_system "$ROOT/tools/caddy-data"
}
$SITES {
	tls internal
	handle /library* {
		reverse_proxy 127.0.0.1:$LIBPORT
	}
	handle_path /tiles/* {
		reverse_proxy 127.0.0.1:8092
	}
	handle_path /voice/* {
		reverse_proxy 127.0.0.1:8093
	}
	handle {
		reverse_proxy 127.0.0.1:$PORT
	}
}
EOF
  "$CADDY" run --config "$CADDYFILE" --adapter caddyfile >"${TMPDIR:-/tmp}/survival-caddy.log" 2>&1 &
  PIDS+=($!)
fi
{ printf '{"port":%s,"ips":[' "$PORT"; first=1; for ip in $IPS; do [ $first = 1 ] || printf ','; printf '"%s"' "$ip"; first=0; done; printf ']'; [ -n "$HTTPSPORT" ] && printf ',"https":%s' "$HTTPSPORT"; printf '}'; } >"$ROOT/portal/kit-address.json" 2>/dev/null

open_url "http://localhost:$PORT/"
echo
echo " READY / PRONTO:  http://localhost:$PORT/"
echo
echo " Phones on the same Wi-Fi or hotspot / Celulares no mesmo Wi-Fi ou roteador:"
if [ "$(uname -s)" = Darwin ]; then
  for ifc in en0 en1 bridge100; do ip=$(ipconfig getifaddr "$ifc" 2>/dev/null) && echo "    http://$ip:$PORT/"; done
else
  for ip in $(hostname -I 2>/dev/null); do case "$ip" in *:*) ;; *) echo "    http://$ip:$PORT/" ;; esac; done
fi
if [ -n "$HTTPSPORT" ]; then
  echo
  echo " Microphone on phones / Microfone no celular:"
  for ip in $IPS; do echo "    https://$ip:$HTTPSPORT/"; done
  echo " The phone warns once that it is \"not private\": choose Advanced / Show details, then continue."
fi
echo
echo " Leave this window open. Press Ctrl+C to SHUT DOWN."
echo " Deixe esta janela aberta. Aperte Ctrl+C para DESLIGAR."
wait
