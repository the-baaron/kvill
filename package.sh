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

# Uploading needs a tool that Apple ships with Xcode or with Transporter, and
# the Command Line Tools alone do not include either. Which one is present
# decides the command, so it is worked out rather than assumed.
upload_tool() {
  if xcrun --find altool > /dev/null 2>&1; then
    echo "altool"
  elif [ -x "/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter" ]; then
    echo "transporter"
  else
    echo "none"
  fi
}

echo
case "$(upload_tool)" in
  altool)      echo "Upload with: ./package.sh --upload   (altool found)" ;;
  transporter) echo "Upload with: ./package.sh --upload   (Transporter found)" ;;
  none)
    echo "No upload tool installed. The package is built and signed, but"
    echo "sending it needs one of:"
    echo "  - Transporter, free on the Mac App Store, the smaller of the two"
    echo "  - Xcode, which brings altool with it"
    ;;
esac

if [ "${1:-}" = "--upload" ]; then
  echo
  echo "==> Uploading to App Store Connect"
  # shellcheck disable=SC1090
  set -a; . "$HOME/.appstoreconnect/env"; set +a
  case "$(upload_tool)" in
    altool)
      xcrun altool --upload-app --type macos --file "$PKG" \
        --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
      ;;
    transporter)
      "/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter" \
        -m upload -assetFile "$PKG" -apiKey "$ASC_KEY_ID" -apiIssuer "$ASC_ISSUER_ID"
      ;;
    none)
      echo "Nothing to upload with. Install Transporter or Xcode first." >&2
      exit 1
      ;;
  esac
fi
