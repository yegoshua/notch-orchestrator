#!/bin/bash
# Throwaway prototype (ticket #3). Quarantine check.
# Serves a zipped test app from a local HTTP server, downloads it with curl (as the planned
# one-line installer would), unpacks it and shows whether com.apple.quarantine is set,
# plus what Gatekeeper's assessment (spctl) says.
#
# Usage: quarantine-check.sh [adhoc|selfsigned]      (default adhoc, version 1.0)
#        quarantine-check.sh --serve [adhoc|selfsigned]   keep serving so the same zip can be
#                                                         downloaded with a BROWSER for comparison
# Nothing is launched. Work dir: signing/.build/quarantine (git-ignored).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/signing/common.sh"

SERVE_ONLY=0
if [ "${1:-}" = "--serve" ]; then SERVE_ONLY=1; shift; fi
VARIANT="${1:-adhoc}"
SRC_APP="$(bundle_path "$VARIANT" 1.0)"
[ -d "$SRC_APP" ] || "$DIR/signing/build.sh" "$VARIANT" || exit 1

WORK="$BUILD_DIR/quarantine"
rm -rf "$WORK"; mkdir -p "$WORK/www" "$WORK/curl"
ZIP_NAME="$APP_NAME-$VARIANT.zip"
ditto -c -k --keepParent "$SRC_APP" "$WORK/www/$ZIP_NAME"

PORT="${PORT:-8765}"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/www" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.3; done

URL="http://127.0.0.1:$PORT/$ZIP_NAME"
if [ "$SERVE_ONLY" = 1 ]; then
  echo "Serving $URL"
  echo "Open that URL in Safari/Chrome, let it download, then compare:"
  echo "  xattr -l ~/Downloads/$ZIP_NAME"
  echo "  xattr -lr ~/Downloads/$APP_NAME.app | grep -c com.apple.quarantine   # after unpacking it in Finder"
  echo "Press Ctrl-C to stop the server."
  wait $SERVER_PID
  exit 0
fi

show_xattr() { # <label> <path>
  echo "--- xattr -l  ($1)"
  local out; out="$(xattr -l "$2" 2>&1)"
  [ -n "$out" ] && echo "$out" || echo "(no extended attributes)"
  if xattr -p com.apple.quarantine "$2" >/dev/null 2>&1; then echo ">>> com.apple.quarantine: PRESENT"; else echo ">>> com.apple.quarantine: absent"; fi
}

echo "### 1. download with curl: $URL"
curl -fsS -o "$WORK/curl/$ZIP_NAME" "$URL" || { echo "download failed"; exit 1; }
show_xattr "archive downloaded with curl" "$WORK/curl/$ZIP_NAME"

echo; echo "### 2. unpack (ditto -x -k, same result expected with unzip / tar)"
ditto -x -k "$WORK/curl/$ZIP_NAME" "$WORK/curl/"
APP="$WORK/curl/$APP_NAME.app"
show_xattr "unpacked app bundle" "$APP"
show_xattr "unpacked executable" "$APP/Contents/MacOS/$APP_NAME"
echo "--- any quarantine attribute anywhere inside the bundle:"
xattr -lr "$APP" 2>/dev/null | grep -c com.apple.quarantine | sed 's/^/count: /'

echo; echo "### 3. Gatekeeper assessment (what it WOULD say if the app were quarantined)"
echo "--- spctl --assess --type execute -vv"
spctl --assess --type execute -vv "$APP" 2>&1; echo "(spctl exit code: $?)"
echo "--- spctl --status"; spctl --status 2>&1

echo; echo "### 4. signature"
codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Signature|Authority|TeamIdentifier)'
codesign -d -r- "$APP" 2>&1 | grep 'designated =>'

cat <<OUT

### Manual step (not done by this script)
Double-click this app in Finder (or: open -n '$APP') and note whether a Gatekeeper dialog appears:
  $APP
Comparison case: run '$0 --serve $VARIANT', download the same zip with a browser, unpack it in
Finder and double-click THAT copy; it should carry com.apple.quarantine and be blocked by Gatekeeper.
OUT
