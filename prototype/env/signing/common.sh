# Throwaway prototype (ticket #3). Shared settings for the signing-test scripts. Source it.
SIGNING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SIGNING_DIR/.build"                 # git-ignored (.build/ in the root .gitignore)
APP_NAME="NotchAETest"
BUNDLE_ID_BASE="dev.notch-orchestrator.aetest"   # + .adhoc / .selfsigned, so the two variants never share a TCC entry
CERT_NAME="${CERT_NAME:-Notch Orchestrator Dev}" # self-signed code-signing certificate, created by hand (see CHECKLIST.md)
INSTALL_DIR="${INSTALL_DIR:-$BUILD_DIR/installed}" # the fixed place where v1.1 replaces v1.0
LOG_PATH="$BUILD_DIR/aetest.log"
VERSIONS=("1.0" "1.1")

bundle_path() { echo "$BUILD_DIR/$1/$2/$APP_NAME.app"; }   # bundle_path <variant> <version>
installed_path() { echo "$INSTALL_DIR/$APP_NAME-$1.app"; } # installed_path <variant>
