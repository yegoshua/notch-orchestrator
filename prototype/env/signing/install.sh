#!/bin/bash
# Throwaway prototype (ticket #3). "Installs" one build to a fixed path, replacing whatever is there,
# the way an updater would. It does NOT launch the app.
# Usage: install.sh adhoc|selfsigned 1.0|1.1
# Fixed path: .build/installed/NotchAETest-<variant>.app  (override the directory with INSTALL_DIR=...)
set -euo pipefail
source "$(dirname "$0")/common.sh"
variant="${1:-}"; version="${2:-}"
[[ "$variant" =~ ^(adhoc|selfsigned)$ && -n "$version" ]] || { echo "usage: $0 adhoc|selfsigned 1.0|1.1" >&2; exit 2; }
src="$(bundle_path "$variant" "$version")"; dst="$(installed_path "$variant")"
[ -d "$src" ] || { echo "ERROR: $src is not built. Run: $SIGNING_DIR/build.sh $variant" >&2; exit 1; }
mkdir -p "$INSTALL_DIR"
rm -rf "$dst"
ditto "$src" "$dst"   # ditto keeps the signature intact
echo "installed $variant v$version -> $dst"
codesign -d -r- "$dst" 2>&1 | grep 'designated =>' | sed 's|^# ||' || true
echo
echo "Launch it (do NOT run the binary directly from a terminal):"
echo "  open -n '$dst'"
echo "Result: the alert, and the last line of $LOG_PATH"
