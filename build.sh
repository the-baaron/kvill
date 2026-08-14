#!/bin/bash
# Assembles Foldout.app from the SwiftPM build product.
#
# Xcode is not required: the Command Line Tools ship the macOS SDK, and the app
# bundle is a directory layout plus an Info.plist, both of which are made here.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/Foldout.app"
CONTENTS="$APP/Contents"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Foldout"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/Foldout"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Rendering icon"
ICONSET="build/Foldout.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/Foldout.icns"
rm -rf "$ICONSET"

echo "==> Signing"
# Ad-hoc, with the real entitlements. The signature is only good on this machine,
# but the sandbox is enforced from the entitlements either way, so what runs here
# behaves like what ships.
#
# QUILL_SANDBOX=0 leaves them off. The sandbox stops the app reading a path
# handed to it on the command line, which is exactly what --render, --benchmark
# and --selftest with a document do, so the development tools need a build
# without it.
if [ "${QUILL_SANDBOX:-1}" = "0" ]; then
  echo "    without the sandbox (QUILL_SANDBOX=0)"
  codesign --force --sign - --timestamp=none "$APP"
else
  codesign --force --sign - --timestamp=none \
    --entitlements Resources/Foldout.entitlements "$APP"
fi

echo "==> Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$(cd "$APP" && pwd)"

# A running copy keeps the code it launched with, so rebuilding under it changes
# nothing on screen. If Foldout was already open, it is restarted onto the new
# build. The quit goes through AppleScript rather than a kill so that documents
# are given the chance to save; if something is holding it up, the restart is
# skipped and said so rather than forced.
if pgrep -f "$(cd "$APP" && pwd)/Contents/MacOS/Foldout" > /dev/null 2>&1; then
  echo "==> Restarting the running copy"
  osascript -e 'quit app "Foldout"' > /dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    pgrep -f "$(cd "$APP" && pwd)/Contents/MacOS/Foldout" > /dev/null 2>&1 || break
    sleep 0.25
  done

  if pgrep -f "$(cd "$APP" && pwd)/Contents/MacOS/Foldout" > /dev/null 2>&1; then
    echo "    Foldout did not quit, most likely an unsaved document is asking."
    echo "    Left it alone. Quit it yourself and run: open $APP"
  else
    open "$APP"
    echo "    Running the new build."
  fi
fi

echo
echo "Built $APP"
echo "Run it with:  open $APP"
echo "Install it with:  cp -R $APP /Applications/"
