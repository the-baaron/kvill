#!/bin/bash
# Assembles Quill.app from the SwiftPM build product.
#
# Xcode is not required: the Command Line Tools ship the macOS SDK, and the app
# bundle is a directory layout plus an Info.plist, both of which are made here.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/Quill.app"
CONTENTS="$APP/Contents"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Quill"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/Quill"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Rendering icon"
ICONSET="build/Quill.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/Quill.icns"
rm -rf "$ICONSET"

echo "==> Signing"
# Ad-hoc signature. Enough for the app to run locally and for Launch Services to
# register it; a Developer ID signature would be needed to distribute it.
codesign --force --sign - --timestamp=none "$APP"

echo "==> Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$(cd "$APP" && pwd)"

echo
echo "Built $APP"
echo "Run it with:  open $APP"
echo "Install it with:  cp -R $APP /Applications/"
