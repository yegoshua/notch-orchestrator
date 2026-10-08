#!/bin/sh
# Draws the app icon anew into packaging/AppIcon.icns. Only needed when scripts/make-icon.swift
# changes: the icon it made is kept in the repository and scripts/build-app.sh copies it.
set -eu
cd "$(dirname "$0")/.."

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil --convert icns --output packaging/AppIcon.icns "$ICONSET"
rm -rf "$(dirname "$ICONSET")"
echo packaging/AppIcon.icns
