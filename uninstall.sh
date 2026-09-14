#!/bin/bash
# uninstall.sh -- remove mdview, the droplet, and (optionally) its state.
#
#   ./uninstall.sh          remove the app and scripts
#   ./uninstall.sh --purge  also delete ~/.local/state/mdview and the config
set -euo pipefail

BIN_DIR="${MDVIEW_BIN_DIR:-$HOME/.local/bin}"
APP_DIR="${MDVIEW_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/px0 Markdown.app"
STATE="${MDVIEW_STATE:-$HOME/.local/state/mdview}"
CONF="${MDVIEW_CONFIG:-$HOME/.config/mdview/config}"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

say() { printf '  %s\n' "$*"; }
echo "Removing px0-md-open"

# Stop anything still running before pulling the scripts out from under it.
if [ -x "$BIN_DIR/mdview" ]; then
  "$BIN_DIR/mdview" --stop-all 2>/dev/null | sed 's/^/  /' || true
fi

if [ -d "$APP" ]; then
  "$LSREG" -u "$APP" 2>/dev/null || true
  rm -rf "$APP"
  say "removed $APP"
fi

for f in "$BIN_DIR/mdview" "$BIN_DIR/mdview-tabcount"; do
  [ -e "$f" ] && { rm -f "$f"; say "removed $f"; }
done

if [ "${1:-}" = "--purge" ]; then
  [ -d "$STATE" ] && { rm -rf "$STATE"; say "removed $STATE"; }
  [ -f "$CONF" ]  && { rm -f  "$CONF";  say "removed $CONF"; }
else
  say "kept $STATE (use --purge to remove)"
fi

cat <<DONE

Done. If "px0 Markdown" still shows under Open With, Finder is holding a
cached association; it clears on the next login.

px0 itself was not touched.
DONE
