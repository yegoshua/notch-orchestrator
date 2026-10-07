#!/bin/sh
# Builds "Notch Orchestrator.app" into .build/app/ as a universal, ad-hoc signed bundle.
# Usage: scripts/build-app.sh [version]
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP=".build/app/Notch Orchestrator.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/NotchApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NotchApp"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>NotchApp</string>
    <key>CFBundleIdentifier</key><string>dev.notch-orchestrator.app</string>
    <key>CFBundleName</key><string>Notch Orchestrator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
