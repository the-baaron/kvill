#!/bin/bash
# Builds the Mac App Store package: a sandboxed, distribution-signed app inside
# a signed installer, ready to upload.
#
# What `build.sh` makes is for this machine: an ad-hoc signature that no other
# Mac trusts. This makes the real thing.
#
#   ./package.sh                 build and sign, leaving build/Kvill.pkg
#   ./package.sh --upload        the same, then hand it to App Store Connect
#
# Credentials for the upload come from ~/.appstoreconnect/env, the same file the
# other App Store scripts read.
set -euo pipefail

cd "$(dirname "$0")"

# A distribution-signed app cannot be launched on this Mac: a Mac App Store
# provisioning profile lists no devices, because the store is the only way in.
# So it is built somewhere of its own rather than over the top of the app you
# actually run, which is what `build.sh` leaves in build/.
DIST="build/dist"
APP="$DIST/Kvill.app"
PKG="build/Kvill.pkg"
APP_IDENTITY="3rd Party Mac Developer Application"
INSTALLER_IDENTITY="3rd Party Mac Developer Installer"
PROFILE="Resources/Kvill.provisionprofile"

for identity in "$APP_IDENTITY" "$INSTALLER_IDENTITY"; do
  if ! security find-identity -v | grep -q "$identity"; then
    echo "Missing signing identity: $identity" >&2
    echo "Both are issued from the App Store Connect API against a local CSR." >&2
    exit 1
  fi
done

echo "==> Building"
QUILL_SANDBOX=1 ./build.sh release > /dev/null
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R build/Kvill.app "$APP"

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

# Two entitlements Xcode injects and a hand-rolled signature does not: the
# application identifier and the team identifier. Without them Apple answers an
# upload with ITMS-90886, because the embedded provisioning profile carries an
# application identifier and the signature has to agree with it.
#
# Derived rather than written down, so they cannot drift from the Info.plist and
# the certificate.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
TEAM_ID="$(security find-certificate -c "$APP_IDENTITY" -p \
  | openssl x509 -noout -subject \
  | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
if [ -z "$TEAM_ID" ]; then
  echo "Could not read the team identifier from the signing certificate." >&2
  exit 1
fi
echo "    $BUNDLE_ID, team $TEAM_ID"

DIST_ENTITLEMENTS="build/distribution.entitlements"
cp Resources/Kvill.entitlements "$DIST_ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" \
  -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
  "$DIST_ENTITLEMENTS" > /dev/null

echo "==> Signing for distribution"
codesign --force --options runtime --timestamp \
  --entitlements "$DIST_ENTITLEMENTS" \
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
