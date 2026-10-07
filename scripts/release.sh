#!/bin/sh
# Builds the release archive of a version: .build/release/NotchOrchestrator-<version>.zip, with
# its checksum beside it. Publishes nothing.
# Usage: scripts/release.sh <version>
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
OUT=".build/release"
ARCHIVE="$OUT/NotchOrchestrator-$VERSION.zip"

APP="$(scripts/build-app.sh "$VERSION" | tail -1)"
codesign --verify --strict "$APP"
mkdir -p "$OUT"
rm -f "$ARCHIVE"
# ditto keeps the signature's extended attributes and symbolic links; zip does not.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" | tee "$ARCHIVE.sha256"
