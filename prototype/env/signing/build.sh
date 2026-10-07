#!/bin/bash
# Throwaway prototype (ticket #3). Builds the AE test app.
# Usage: build.sh adhoc|selfsigned|all
# Produces .build/<variant>/<version>/NotchAETest.app for versions 1.0 and 1.1.
set -euo pipefail
source "$(dirname "$0")/common.sh"

build_one() { # <variant> <version>
  local variant="$1" version="$2" app; app="$(bundle_path "$variant" "$version")"
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  # The version is also compiled into the binary so that 1.0 and 1.1 really differ in code (different cdhash).
  sed "s/^let app = NSApplication.shared/let buildMarker = \"build-$version\"; _ = buildMarker\\
let app = NSApplication.shared/" "$SIGNING_DIR/main.swift" > "$BUILD_DIR/main-$variant-$version.swift"
  swiftc -O -o "$app/Contents/MacOS/$APP_NAME" "$BUILD_DIR/main-$variant-$version.swift"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID_BASE.$variant</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Prototype check: asks Terminal how many windows it has.</string>
  <key>AETestVariant</key><string>$variant</string>
  <key>AETestLogPath</key><string>$LOG_PATH</string>
</dict></plist>
PLIST
  if [ "$variant" = adhoc ]; then
    codesign --force --sign - "$app"
  else
    codesign --force --sign "$CERT_NAME" "$app"
  fi
  codesign --verify --strict "$app"
  echo "built $app"
}

require_cert() {
  # A self-signed certificate is not trusted, so it is not listed as "valid": do not pass -v.
  if ! security find-identity -p codesigning | grep -F "\"$CERT_NAME\"" >/dev/null; then
    cat >&2 <<MSG
ERROR: code-signing certificate "$CERT_NAME" was not found in your keychains.
Create it by hand first (Keychain Access > Certificate Assistant > Create a Certificate...,
Name "$CERT_NAME", Identity Type "Self Signed Root", Certificate Type "Code Signing").
Full steps: prototype/env/CHECKLIST.md, section "Signing".
To use another name: CERT_NAME="My Cert" $0 selfsigned
MSG
    exit 1
  fi
}

mkdir -p "$BUILD_DIR"
case "${1:-}" in
  adhoc)      for v in "${VERSIONS[@]}"; do build_one adhoc "$v"; done ;;
  selfsigned) require_cert; for v in "${VERSIONS[@]}"; do build_one selfsigned "$v"; done ;;
  all)        for v in "${VERSIONS[@]}"; do build_one adhoc "$v"; done
              require_cert; for v in "${VERSIONS[@]}"; do build_one selfsigned "$v"; done ;;
  *) echo "usage: $0 adhoc|selfsigned|all" >&2; exit 2 ;;
esac
