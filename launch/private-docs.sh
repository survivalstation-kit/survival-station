#!/usr/bin/env bash
# Survival Station private documents on Mac and Linux: the same locked files as PRIVATE-DOCS.bat on Windows
# (OpenSSL format: aes-256-cbc, PBKDF2-SHA256, 200,000 rounds). Usage: bash launch/private-docs.sh [lock|open|close]
cd "$(dirname "$0")/.." || exit 1
PRIV="$(pwd)/private"
OPENED="${TMPDIR:-/tmp}/survival-private"
CHECK="$PRIV/.password-check.locked"
OSSL=(openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -md sha256)
mkdir -p "$PRIV"
command -v openssl >/dev/null || { echo " openssl is needed (it comes with macOS and most Linux systems)."; exit 1; }

ask() { read -r -s -p " $1: " REPLY; echo; }
check_password() {   # the kit's password opens the check file; with none yet, this password starts the lock
  if [ -f "$CHECK" ]; then
    [ "$("${OSSL[@]}" -d -in "$CHECK" -pass "pass:$PW" 2>/dev/null)" = "survival-station-private" ] || { echo " Wrong password."; exit 1; }
  else
    [ ${#PW} -ge 6 ] || { echo " Choose a password of at least 6 characters."; exit 1; }
    ask "Same password again / Repita a senha"; [ "$REPLY" = "$PW" ] || { echo " The two passwords are different."; exit 1; }
    printf 'survival-station-private' | "${OSSL[@]}" -salt -out "$CHECK" -pass "pass:$PW"
    echo " Write the password down and keep it safe: without it the files can't be opened."
  fi
}

case "${1:-}" in
  lock)
    ask "Password / Senha"; PW=$REPLY; check_password
    n=0
    while IFS= read -r -d '' f; do
      "${OSSL[@]}" -salt -in "$f" -out "$f.locked" -pass "pass:$PW" && cmp -s <("${OSSL[@]}" -d -in "$f.locked" -pass "pass:$PW") "$f" && rm -f "$f" && n=$((n + 1))
    done < <(find "$PRIV" -type f ! -name '*.locked' -print0)
    echo " Locked $n file(s)." ;;
  open)
    [ -f "$CHECK" ] || { echo " Nothing is locked on this kit yet."; exit 1; }
    ask "Password / Senha"; PW=$REPLY; check_password
    rm -rf "$OPENED"; mkdir -p "$OPENED"
    while IFS= read -r -d '' f; do
      rel="${f#"$PRIV"/}"; out="$OPENED/${rel%.locked}"
      mkdir -p "$(dirname "$out")"; "${OSSL[@]}" -d -in "$f" -out "$out" -pass "pass:$PW"
    done < <(find "$PRIV" -type f -name '*.locked' ! -name '.password-check.locked' -print0)
    echo " Opened in $OPENED. Run 'bash launch/private-docs.sh close' when you finish."
    if command -v open >/dev/null; then open "$OPENED"; else xdg-open "$OPENED" >/dev/null 2>&1 & fi ;;
  close)
    rm -rf "$OPENED"; echo " Closed: the opened copies were deleted from this computer."
    echo " (To keep a changed file: copy it into the private folder and lock again.)" ;;
  *) echo " Usage: bash launch/private-docs.sh lock | open | close"; echo " Your files go in: $PRIV" ;;
esac