#!/bin/bash
# smoke.sh -- exercise mdview without needing a real browser.
#
# The browser is stubbed two ways: `open` is shadowed on PATH so no window
# appears, and MDVIEW_TABCOUNT points at a fake whose answer we control via a
# file. That lets us drive the "tab closed" transition deterministically.
#
#   ./test/smoke.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MDVIEW="$REPO/bin/mdview"
TMP="$(mktemp -d)"
PASS=0; FAIL=0

cleanup() {
  MDVIEW_STATE="$TMP/state" "$MDVIEW" --stop-all >/dev/null 2>&1 || true
  pkill -f "px0 -no-open -no-lsp -port 0 $TMP" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
nope() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
is()   { [ "$2" = "$3" ] && ok "$1" || nope "$1 (want '$3', got '$2')"; }

# ---- fixtures ---------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/ws/docs" "$TMP/other"
printf '#!/bin/bash\necho "STUB-OPEN $*" >> '"$TMP"'/opened\n' > "$TMP/bin/open"
chmod +x "$TMP/bin/open"

echo 1 > "$TMP/tabs"
printf '#!/bin/bash\ncat '"$TMP"'/tabs\n' > "$TMP/bin/tabcount"
chmod +x "$TMP/bin/tabcount"

printf '# A\n' > "$TMP/ws/notes.md"
printf '# B\n' > "$TMP/ws/docs/b.md"
printf '# C\n' > "$TMP/other/c.md"
( cd "$TMP/ws" && git init -q )

export PATH="$TMP/bin:$PATH"
export MDVIEW_STATE="$TMP/state"
export MDVIEW_TABCOUNT="$TMP/bin/tabcount"
export MDVIEW_CONFIG=/dev/null
export MDVIEW_GRACE=15 MDVIEW_IDLE=4 MDVIEW_POLL=1
REG="$TMP/state/registry"

if ! command -v px0 >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/px0" ]; then
  echo "smoke.sh: px0 not installed; skipping." >&2
  exit 77
fi

echo "smoke tests"

# ---- 1. first open ----------------------------------------------------------
out="$("$MDVIEW" "$TMP/ws/notes.md" 2>&1)"
p1="$(awk -F'\t' '{print $2}' "$REG" | head -1)"
[ -n "$p1" ] && ok "first open starts a server (port $p1)" || nope "first open: no port in registry"
case "$out" in *"notes.md -> http://127.0.0.1:$p1"*) ok "prints the URL";; *) nope "prints the URL (got: $out)";; esac
grep -q "STUB-OPEN" "$TMP/opened" 2>/dev/null && ok "hands the URL to the browser" || nope "browser not invoked"

# ---- 2. reuse within one workspace -----------------------------------------
"$MDVIEW" "$TMP/ws/docs/b.md" >/dev/null 2>&1
p2="$(awk -F'\t' '{print $2}' "$REG" | head -1)"
is "second file in same repo reuses the server" "$p2" "$p1"
is "registry still has one row" "$(wc -l < "$REG" | tr -d ' ')" "1"

# ---- 3. git root, not the file's directory ---------------------------------
root="$(awk -F'\t' '{print $1}' "$REG" | head -1)"
is "workspace root is the git top-level" "$root" "$(cd "$TMP/ws" && pwd -P)"

# ---- 4. a separate workspace gets its own server ---------------------------
"$MDVIEW" "$TMP/other/c.md" >/dev/null 2>&1
is "unrelated directory starts a second server" "$(wc -l < "$REG" | tr -d ' ')" "2"
p3="$(awk -F'\t' -v r="$(cd "$TMP/other" && pwd -P)" '$1==r {print $2}' "$REG")"
[ -n "$p3" ] && [ "$p3" != "$p1" ] && ok "second server is on its own port" || nope "second server port"

# ---- 5. shutdown when the last tab goes away -------------------------------
echo 0 > "$TMP/tabs"
gone=0
for _ in $(seq 1 20); do
  sleep 1
  [ "$(awk -F'\t' '{print $2}' "$REG" | grep -c "^$p1$")" -eq 0 ] && { gone=1; break; }
done
is "server stops after its last tab closes" "$gone" "1"

# ---- 6. stale rows are pruned ----------------------------------------------
echo 1 > "$TMP/tabs"
printf '%s\t%s\t%s\n' "/nonexistent" "65000" "999999" >> "$REG"
"$MDVIEW" "$TMP/ws/notes.md" >/dev/null 2>&1
is "dead rows are pruned" "$(grep -c '^/nonexistent' "$REG" || true)" "0"

# ---- 7. --stop-all ----------------------------------------------------------
"$MDVIEW" --stop-all >/dev/null 2>&1
is "--stop-all empties the registry" "$(wc -l < "$REG" | tr -d ' ')" "0"

# ---- 8. error handling ------------------------------------------------------
"$MDVIEW" "$TMP/nope.md" >/dev/null 2>&1
is "missing file exits non-zero" "$?" "1"
HOME="$TMP/fakehome" PX0_BIN=/nonexistent/px0 PATH="$TMP/bin:/usr/bin:/bin" \
  "$MDVIEW" "$TMP/ws/notes.md" >/dev/null 2>&1
is "missing px0 exits non-zero" "$?" "1"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
