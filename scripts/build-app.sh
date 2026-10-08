#!/bin/sh
# Builds "Notch Orchestrator.app" into .build/app/ as a universal bundle, ad-hoc signed by default.
# Usage: scripts/build-app.sh [version]
# NOTCH_SIGN_IDENTITY names the certificate to sign with instead: with the same certificate every
# build is the same app to macOS, so the permissions granted to one carry over to the next.
# The app updates itself only when scripts/sparkle-public-key holds the update key (see README).
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
APP=".build/app/Notch Orchestrator.app"
IDENTITY="${NOTCH_SIGN_IDENTITY:--}"
FEED="https://github.com/yegoshua/notch-orchestrator/releases/latest/download/appcast.xml"

swift build -c release --arch arm64 --arch x86_64
PRODUCTS="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

UPDATES=""
if [ -s scripts/sparkle-public-key ]; then
    UPDATES="<key>SUFeedURL</key><string>$FEED</string>
    <key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < scripts/sparkle-public-key)</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$PRODUCTS/NotchApp" "$APP/Contents/MacOS/NotchApp"
# Drawn by scripts/make-icon.sh.
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# ditto keeps the framework's symbolic links; cp -R would not on every system.
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>NotchApp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>dev.notch-orchestrator.app</string>
    <key>CFBundleName</key><string>Notch Orchestrator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Brings forward the Terminal tab a session runs in when you click the session, and tells whether that tab is already in front before interrupting you.</string>
    $UPDATES
</dict>
</plist>
PLIST

# Inside out, as Sparkle asks: its helpers, the framework, then the app. Without the hardened
# runtime: it would refuse to load a framework that no Apple team signed.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPARKLE/XPCServices/Installer.xpc" "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework" "$APP"; do
    codesign --force --sign "$IDENTITY" ${NOTCH_KEYCHAIN:+--keychain "$NOTCH_KEYCHAIN"} "$part" 2>/dev/null
done
codesign --verify --deep --strict "$APP"
echo "$APP"
