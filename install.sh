#!/bin/bash
# install.sh -- install mdview and the "px0 Markdown" Finder droplet.
#
#   ./install.sh              install for the current user
#   ./install.sh --default    also make it the default handler for .md
#
# Everything lands under your home directory; nothing needs sudo.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${MDVIEW_BIN_DIR:-$HOME/.local/bin}"
APP_DIR="${MDVIEW_APP_DIR:-$HOME/Applications}"
APP_NAME="px0 Markdown"
APP="$APP_DIR/$APP_NAME.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

MAKE_DEFAULT=0
[ "${1:-}" = "--default" ] && MAKE_DEFAULT=1

say() { printf '  %s\n' "$*"; }

[ "$(uname -s)" = "Darwin" ] || { echo "install.sh: macOS only (needs Launch Services + AppleScript)" >&2; exit 1; }

echo "Installing px0-md-open"

# ---- 1. px0 itself ----------------------------------------------------------
if command -v px0 >/dev/null 2>&1; then
  say "found px0: $(command -v px0) ($(px0 -v 2>/dev/null | head -1))"
elif [ -x "$HOME/.local/bin/px0" ]; then
  say "found px0: $HOME/.local/bin/px0"
else
  say "WARNING: px0 not found on PATH."
  say "         Install it from https://px0.ai first, or set PX0_BIN."
fi

# ---- 2. scripts -------------------------------------------------------------
mkdir -p "$BIN_DIR"
install -m 0755 "$SRC/bin/mdview"          "$BIN_DIR/mdview"
install -m 0755 "$SRC/bin/mdview-tabcount" "$BIN_DIR/mdview-tabcount"
say "installed $BIN_DIR/mdview"
say "installed $BIN_DIR/mdview-tabcount"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "note: $BIN_DIR is not on your PATH (the .app works regardless)" ;;
esac

# ---- 3. the droplet ---------------------------------------------------------
mkdir -p "$APP_DIR"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Bake the absolute path in: `do shell script` runs with a minimal PATH.
sed "s|__MDVIEW__|$BIN_DIR/mdview|" "$SRC/app/mdview.applescript" > "$work/mdview.applescript"

rm -rf "$APP"
osacompile -o "$APP" "$work/mdview.applescript"
say "compiled $APP"

# ---- 4. declare it a Markdown (and folder) viewer --------------------------
PL="$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
# Keep each PlistBuddy run to 14 commands or fewer. Past that it does not
# report an error, it aborts (signal 6) and writes nothing -- so the entries
# below are split across invocations rather than chained into one.
#
# LSHandlerRank Alternate => shows up under "Open With" without stealing the
# default association from whatever the user already uses. The folder entry is
# rank None: Finder has no "Open With" menu on folders anyway, and None keeps
# us out of the running for anything that does dispatch on public.folder. It is
# there so a folder can be dropped on the app, not to claim folders.
$PB -c "Delete :CFBundleDocumentTypes" "$PL" 2>/dev/null || true
$PB -c "Add :CFBundleDocumentTypes array" \
    -c "Add :CFBundleDocumentTypes:0 dict" \
    -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'Markdown Document'" \
    -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" \
    -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" \
    -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" \
    -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string net.daringfireball.markdown" \
    -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" \
    -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string md" \
    -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:1 string markdown" \
    -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:2 string mdown" \
    -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:3 string mkd" \
    "$PL" >/dev/null
$PB -c "Add :CFBundleDocumentTypes:1 dict" \
    -c "Add :CFBundleDocumentTypes:1:CFBundleTypeName string 'Folder'" \
    -c "Add :CFBundleDocumentTypes:1:CFBundleTypeRole string Viewer" \
    -c "Add :CFBundleDocumentTypes:1:LSHandlerRank string None" \
    -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes array" \
    -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes:0 string public.folder" \
    -c "Add :CFBundleIdentifier string ai.px0.mdview" \
    "$PL" >/dev/null
say "declared .md / .markdown / .mdown / .mkd, and folders"

# Editing Info.plist invalidates osacompile's ad-hoc signature; re-sign.
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || say "note: could not re-sign (harmless)"
"$LSREG" -f "$APP" || true
say "registered with Launch Services"

# ---- 5. optional: become the default ---------------------------------------
if [ "$MAKE_DEFAULT" -eq 1 ]; then
  if command -v duti >/dev/null 2>&1; then
    duti -s ai.px0.mdview net.daringfireball.markdown all && say "set as default handler for .md"
  else
    say "note: --default needs duti (brew install duti)."
    say "      Or: Finder > Get Info on a .md > Open With > $APP_NAME > Change All."
  fi
fi

cat <<DONE

Done.

  Right-click any .md file -> Open With -> "$APP_NAME"
  Drag a folder onto the app to browse that whole tree in px0.
  Or from a terminal:       mdview path/to/file.md
                            mdview path/to/folder

The first time the shutdown watcher runs, macOS will ask for permission to
control your browser. Allow it, or the server will not stop on tab close.

Config (optional): ~/.config/mdview/config
  MDVIEW_BROWSER="Google Chrome"   # Brave Browser, Safari, Arc, ...
  MDVIEW_IDLE=1800                 # seconds after last tab closes
DONE
