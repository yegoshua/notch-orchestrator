#!/bin/sh
# Creates the self-signed certificate releases are signed with and puts it into your login
# keychain. Run it once, by hand: it adds a signing identity to your keychain, which is yours to do.
# Usage: scripts/create-signing-certificate.sh ["Certificate Name"]
#
# macOS tells one app from another by this certificate, so every release has to be signed with
# the same one or the permissions people granted are asked for again. Back it up: export it from
# Keychain Access (My Certificates) with its private key and keep the file somewhere safe.
set -eu

NAME="${1:-Notch Orchestrator Release}"
KEYCHAIN="${NOTCH_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\"" >/dev/null; then
    echo "A certificate named \"$NAME\" is already there; nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/certificate.conf" <<CONF
[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = $NAME
[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF
# The system's own openssl: what it writes is what the keychain reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/certificate.conf" \
    -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
PASSWORD="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$PASSWORD"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null

# Not "valid" in the system's eyes, since nobody vouches for it; it signs all the same.
security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""
echo "Created \"$NAME\". Build a release with: NOTCH_SIGN_IDENTITY=\"$NAME\" scripts/release.sh <version>"
