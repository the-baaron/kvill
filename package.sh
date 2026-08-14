#!/bin/bash
# Builds the Mac App Store package: a sandboxed, distribution-signed app inside
# a signed installer, ready to upload.
#
# What `build.sh` makes is for this machine: an ad-hoc signature that no other
# Mac trusts. This makes the real thing.
#
#   ./package.sh                 build and sign, leaving build/Signet.pkg
#   ./package.sh --upload        the same, then hand it to App Store Connect
#
# Credentials for the upload come from ~/.appstoreconnect/env, the same file the
# other App Store scripts read.
set -euo pipefail

cd "$(dirname "$0")"

APP="build/Signet.app"
PKG="build/Signet.pkg"
APP_IDENTITY="3rd Party Mac Developer Application"
INSTALLER_IDENTITY="3rd Party Mac Developer Installer"
PROFILE="Resources/Signet.provisionprofile"

for identity in "$APP_IDENTITY" "$INSTALLER_IDENTITY"; do
  if ! security find-identity -v | grep -q "$identity"; then
    echo "Missing signing identity: $identity" >&2
    echo "Both are issued from the App Store Connect API against a local CSR." >&2
    exit 1
  fi
done

echo "==> Building"
QUILL_SANDBOX=1 ./build.sh release > /dev/null

# The App Store rejects an app without a provisioning profile inside it, which
# is issued against a registered bundle identifier.
if [ -f "$PROFILE" ]; then
  echo "==> Embedding the provisioning profile"
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
else
  echo "==> No provisioning profile at $PROFILE"
  echo "    The package will build and can be checked, but App Store Connect"
  echo "    will refuse it until one is issued for the bundle identifier."
fi

echo "==> Signing for distribution"
codesign --force --options runtime --timestamp \
  --entitlements Resources/Signet.entitlements \
  --sign "$APP_IDENTITY" "$APP"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Building the installer"
rm -f "$PKG"
productbuild --component "$APP" /Applications \
  --sign "$INSTALLER_IDENTITY" "$PKG" > /dev/null

echo
echo "Built $PKG"
ls -lh "$PKG" | awk '{print "     " $5}'

if [ "${1:-}" = "--upload" ]; then
  echo
  echo "==> Uploading to App Store Connect"
  # shellcheck disable=SC1090
  set -a; . "$HOME/.appstoreconnect/env"; set +a
  xcrun altool --upload-app --type macos --file "$PKG" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi
