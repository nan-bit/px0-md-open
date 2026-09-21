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
  pkill -f "px0 .*-port 0 $TMP" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$*"; }
nope() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
is()   { [ "$2" = "$3" ] && ok "$1" || nope "$1 (want '$3', got '$2')"; }

# ---- fixtures ---------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/ws/docs" "$TMP/other/sub"
printf '#!/bin/bash\necho "STUB-OPEN $*" >> '"$TMP"'/opened\n' > "$TMP/bin/open"
chmod +x "$TMP/bin/open"

echo 1 > "$TMP/tabs"
printf '#!/bin/bash\ncat '"$TMP"'/tabs\n' > "$TMP/bin/tabcount"
chmod +x "$TMP/bin/tabcount"

printf '# A\n' > "$TMP/ws/notes.md"
printf '# B\n' > "$TMP/ws/docs/b.md"
printf '# C\n' > "$TMP/other/c.md"
printf '# D\n' > "$TMP/other/sub/d.md"
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
is "a file below the open root reuses the server" "$p2" "$p1"
is "registry still has one row" "$(wc -l < "$REG" | tr -d ' ')" "1"

# ---- 3. the file's directory is the root ------------------------------------
root="$(awk -F'\t' '{print $1}' "$REG" | head -1)"
is "workspace root is the file's directory" "$root" "$(cd "$TMP/ws" && pwd -P)"

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

# ---- 7b. a file does not climb to the git top-level ------------------------
# $TMP/ws is a repo and docs/ is inside it, but opening docs/b.md with nothing
# else running must root at docs/, not drag the whole repo into the sidebar.
"$MDVIEW" "$TMP/ws/docs/b.md" >/dev/null 2>&1
is "a file roots at its own directory, not the repo" \
   "$(awk -F'\t' '{print $1}' "$REG" | head -1)" "$(cd "$TMP/ws/docs" && pwd -P)"
"$MDVIEW" --stop-all >/dev/null 2>&1

# ...unless you ask for the old behaviour.
MDVIEW_FILE_ROOT=git "$MDVIEW" "$TMP/ws/docs/b.md" >/dev/null 2>&1
is "MDVIEW_FILE_ROOT=git climbs to the git top-level" \
   "$(awk -F'\t' '{print $1}' "$REG" | head -1)" "$(cd "$TMP/ws" && pwd -P)"
"$MDVIEW" --stop-all >/dev/null 2>&1

# ---- 8. opening a directory -------------------------------------------------
# A directory is taken at its word: $TMP/ws is a git repo, but asking for
# docs/ must not climb to it -- nor drop to docs/'s parent, which is what
# dirname would have done.
"$MDVIEW" "$TMP/ws/docs" >/dev/null 2>&1
is "a directory is its own root" \
   "$(awk -F'\t' '{print $1}' "$REG" | head -1)" "$(cd "$TMP/ws/docs" && pwd -P)"
"$MDVIEW" --stop-all >/dev/null 2>&1

# Finder hands folders over with a trailing slash.
"$MDVIEW" "$TMP/ws/docs/" >/dev/null 2>&1
is "a trailing slash is stripped" \
   "$(awk -F'\t' '{print $1}' "$REG" | head -1)" "$(cd "$TMP/ws/docs" && pwd -P)"
"$MDVIEW" --stop-all >/dev/null 2>&1

# ---- 8b. the browser is pointed at the file, not just the workspace --------
# px0 0.1.7+ reads ?path= and opens that file; older px0 ignores it. ws/ is
# opened first so the file lands inside a wider root and ?path= has to carry a
# sub-directory, which is where the encoding is worth checking.
"$MDVIEW" --stop-all >/dev/null 2>&1
"$MDVIEW" "$TMP/ws" >/dev/null 2>&1
: > "$TMP/opened"
"$MDVIEW" "$TMP/ws/docs/b.md" >/dev/null 2>&1
case "$(cat "$TMP/opened")" in
  *"?path=docs/b.md"*) ok "a file is handed over as ?path=" ;;
  *) nope "a file is handed over as ?path= (got: $(cat "$TMP/opened"))" ;;
esac
"$MDVIEW" --stop-all >/dev/null 2>&1

: > "$TMP/opened"
"$MDVIEW" "$TMP/ws/docs" >/dev/null 2>&1
case "$(cat "$TMP/opened")" in
  *"?path="*) nope "a directory gets no ?path= (got: $(cat "$TMP/opened"))" ;;
  *) ok "a directory gets no ?path=" ;;
esac
"$MDVIEW" --stop-all >/dev/null 2>&1

# A name needing escaping must survive the trip.
mkdir -p "$TMP/ws/my docs"
printf '# S\n' > "$TMP/ws/my docs/a b.md"
"$MDVIEW" "$TMP/ws" >/dev/null 2>&1
: > "$TMP/opened"
"$MDVIEW" "$TMP/ws/my docs/a b.md" >/dev/null 2>&1
case "$(cat "$TMP/opened")" in
  *"?path=my%20docs/a%20b.md"*) ok "spaces in the path are percent-encoded" ;;
  *) nope "spaces in the path are percent-encoded (got: $(cat "$TMP/opened"))" ;;
esac
"$MDVIEW" --stop-all >/dev/null 2>&1

# ---- 9. a file inside an open workspace reuses it ---------------------------
# $TMP/other is not a repo, so d.md alone would root at other/sub. With
# other/ already served, it should land there instead of starting a second px0.
"$MDVIEW" "$TMP/other" >/dev/null 2>&1
pd="$(awk -F'\t' '{print $2}' "$REG" | head -1)"
"$MDVIEW" "$TMP/other/sub/d.md" >/dev/null 2>&1
is "a file under an open directory reuses that server" \
   "$(awk -F'\t' '{print $2}' "$REG" | head -1)" "$pd"
is "no second server below it" "$(wc -l < "$REG" | tr -d ' ')" "1"
"$MDVIEW" --stop-all >/dev/null 2>&1

# ---- 10. error handling -----------------------------------------------------
"$MDVIEW" "$TMP/no-such-dir" >/dev/null 2>&1
is "missing directory exits non-zero" "$?" "1"
"$MDVIEW" "$TMP/nope.md" >/dev/null 2>&1
is "missing file exits non-zero" "$?" "1"
HOME="$TMP/fakehome" PX0_BIN=/nonexistent/px0 PATH="$TMP/bin:/usr/bin:/bin" \
  "$MDVIEW" "$TMP/ws/notes.md" >/dev/null 2>&1
is "missing px0 exits non-zero" "$?" "1"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
