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
  (cd "$ROOT/library" && exec "$KIWIX/kiwix-serve" --port "$LIBPORT" "${ZIMS[@]##*/}") >"${TMPDIR:-/tmp}/survival-kiwix.log" 2>&1 &
  PIDS+=($!)
  echo " Library: ${#ZIMS[@]} archive(s) on port $LIBPORT"
else
  echo " Library server not started (no .zim files, or no kiwix build for $OS)."
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
  echo "   $((i + 1)). $name"
  case "$name" in *Qwen3-4B*) DEF=$((i + 1)) ;; esac
done
PICK=$DEF
if [ ${#MODELS[@]} -gt 1 ]; then
  echo
  read -r -t 10 -p "  Choose AI model [1-${#MODELS[@]}] (default $DEF; use a smaller one on old computers): " PICK
  [[ "$PICK" =~ ^[0-9]+$ ]] && [ "$PICK" -ge 1 ] && [ "$PICK" -le ${#MODELS[@]} ] || PICK=$DEF
  echo
fi
MODEL="${MODELS[$((PICK - 1))]}"
echo " Starting AI with $(basename "$MODEL") ..."

export LD_LIBRARY_PATH="$ENGINE:$LD_LIBRARY_PATH" DYLD_LIBRARY_PATH="$ENGINE:$DYLD_LIBRARY_PATH"
"$ENGINE/llama-server" -m "$MODEL" --host 0.0.0.0 --port "$PORT" --path "$ROOT/portal" -c 8192 \
  >"${TMPDIR:-/tmp}/survival-ai.log" 2>&1 &
AI_PID=$!
PIDS+=($AI_PID)

echo " Waiting for the AI to load ... / Carregando a IA, pode levar um minuto..."
for _ in $(seq 180); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" && break
  kill -0 "$AI_PID" 2>/dev/null || { echo " AI failed to start. Log: ${TMPDIR:-/tmp}/survival-ai.log"; tail -5 "${TMPDIR:-/tmp}/survival-ai.log"; break; }
  sleep 1
done

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
echo
echo " Leave this window open. Press Ctrl+C to SHUT DOWN."
echo " Deixe esta janela aberta. Aperte Ctrl+C para DESLIGAR."
wait
