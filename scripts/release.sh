#!/bin/sh
# Builds everything a release consists of into .build/release/: the app archive, the update feed
# that points at it, the installer and the Homebrew cask. Publishes nothing; the command that
# does is printed at the end.
# Usage: NOTCH_SIGN_IDENTITY="Notch Orchestrator Release" scripts/release.sh <version>
#
# Needs the signing certificate (scripts/create-signing-certificate.sh) and the update key: its
# public half in scripts/sparkle-public-key, its private half in your login keychain (see README).
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
REPO="yegoshua/notch-orchestrator"
OUT=".build/release"
ARCHIVE="$OUT/NotchOrchestrator.zip"
TOOLS=".build/artifacts/sparkle/Sparkle/bin"

: "${NOTCH_SIGN_IDENTITY:?set NOTCH_SIGN_IDENTITY to the name of the signing certificate: an ad-hoc signed release loses its permissions with every update}"
[ -s scripts/sparkle-public-key ] || {
    echo "scripts/sparkle-public-key is missing: a release without the update key cannot update itself" >&2
    exit 1
}

APP="$(scripts/build-app.sh "$VERSION" | tail -1)"
rm -rf "$OUT"
mkdir -p "$OUT"
# ditto keeps the signature's extended attributes and symbolic links; zip does not.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
# Signs the archive with the update key and writes the feed. NOTCH_UPDATE_KEY_FILE names a file
# with the private key, for a machine whose keychain does not hold it.
"$TOOLS/generate_appcast" ${NOTCH_UPDATE_KEY_FILE:+--ed-key-file "$NOTCH_UPDATE_KEY_FILE"} \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    -o "$OUT/appcast.xml" "$OUT"
cp scripts/install.sh "$OUT/install.sh"
SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" packaging/notch-orchestrator.rb > "$OUT/notch-orchestrator.rb"

echo
echo "Built $VERSION into $OUT. To publish:"
echo "  gh release create v$VERSION $ARCHIVE $OUT/appcast.xml $OUT/install.sh --title v$VERSION --generate-notes"
echo "and put $OUT/notch-orchestrator.rb into Casks/ of the tap."
