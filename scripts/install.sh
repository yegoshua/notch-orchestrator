#!/bin/sh
# Installs Notch Orchestrator, or replaces the copy that is there with the latest release:
#   curl -fsSL https://github.com/yegoshua/notch-orchestrator/releases/latest/download/install.sh | sh
#
# The app is not notarized by Apple, so macOS would refuse a copy a browser downloaded. A file
# fetched by curl is not marked as downloaded, which is why this is the way to install it.
set -eu

REPO="yegoshua/notch-orchestrator"
NAME="Notch Orchestrator.app"
BUNDLE_ID="dev.notch-orchestrator.app"
ARCHIVE_URL="${NOTCH_ARCHIVE_URL:-https://github.com/$REPO/releases/latest/download/NotchOrchestrator.zip}"

[ "$(uname -s)" = Darwin ] || { echo "Notch Orchestrator runs on macOS only." >&2; exit 1; }
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || { echo "Notch Orchestrator needs macOS 14 or later." >&2; exit 1; }

# The Applications folder of the machine, or the user's own where that one is not theirs to write.
DESTINATION="${NOTCH_INSTALL_DIR:-/Applications}"
if [ ! -w "$DESTINATION" ]; then
    DESTINATION="$HOME/Applications"
    mkdir -p "$DESTINATION"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "Downloading Notch Orchestrator…"
curl -fsSL -o "$WORK/app.zip" "$ARCHIVE_URL"
ditto -x -k "$WORK/app.zip" "$WORK"
[ -d "$WORK/$NAME" ] || { echo "The archive does not hold the app." >&2; exit 1; }
codesign --verify --deep --strict "$WORK/$NAME" || { echo "The app in the archive is damaged." >&2; exit 1; }

# The copy that runs lets go of its connection to Claude Code's sessions by itself.
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
rm -rf "$DESTINATION/$NAME"
ditto "$WORK/$NAME" "$DESTINATION/$NAME"
xattr -dr com.apple.quarantine "$DESTINATION/$NAME" 2>/dev/null || true
open "$DESTINATION/$NAME"
echo "Installed to $DESTINATION/$NAME. It lives in the notch and in the menu bar."
