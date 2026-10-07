#!/bin/bash
# Throwaway prototype (ticket #3). Prints the designated requirement (DR) of every built and
# installed bundle. TCC stores the DR of the app it granted a permission to; a new build keeps
# the permission only if it still satisfies that stored requirement.
source "$(dirname "$0")/common.sh"
shopt -s nullglob
for app in "$BUILD_DIR"/adhoc/*/"$APP_NAME.app" "$BUILD_DIR"/selfsigned/*/"$APP_NAME.app" "$INSTALL_DIR"/*.app; do
  echo "== ${app#$BUILD_DIR/}"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" | paste -sd' ' -
  codesign -dvvv "$app" 2>&1 | grep -E '^(Signature|Authority|CDHash|TeamIdentifier)' | sed 's/^/   /'
  codesign -d -r- "$app" 2>&1 | grep 'designated =>' | sed 's|^# ||' | sed 's/^/   /'
  echo
done
