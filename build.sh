#!/bin/bash
# Assembles Kvill.app from the SwiftPM build product.
#
# Xcode is not required: the Command Line Tools ship the macOS SDK, and the app
# bundle is a directory layout plus an Info.plist, both of which are made here.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/Kvill.app"
CONTENTS="$APP/Contents"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Kvill"

# KVILL_UNIVERSAL=1 adds the Intel slice. Off by default because it doubles the
# build and nothing on this machine runs it; package.sh turns it on, because
# what ships has to run on both kinds of Mac.
#
# `swift build --arch arm64 --arch x86_64` is the obvious way and cannot be used
# here: it needs xcbuild, which comes with full Xcode, and only the Command Line
# Tools are installed. So each slice is built separately and joined with lipo.
if [ "${KVILL_UNIVERSAL:-0}" = "1" ]; then
  MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
  echo "==> Building the Intel slice (macOS $MIN_OS)"
  INTEL_FLAGS=(-Xswiftc -target -Xswiftc "x86_64-apple-macos$MIN_OS")
  swift build -c "$CONFIG" --scratch-path .build-x86_64 "${INTEL_FLAGS[@]}"
  # The scratch directory is named after the *host* triple whatever -target
  # says, so the path claims arm64 while holding an Intel binary. lipo is the
  # only thing here worth believing.
  INTEL="$(swift build -c "$CONFIG" --scratch-path .build-x86_64 \
    "${INTEL_FLAGS[@]}" --show-bin-path)/Kvill"
  if [ "$(lipo -archs "$INTEL")" != "x86_64" ]; then
    echo "    the Intel slice came out as $(lipo -archs "$INTEL"), not x86_64" >&2
    exit 1
  fi
  lipo -create "$BINARY" "$INTEL" -output build/Kvill-universal
  BINARY="build/Kvill-universal"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/Kvill"
cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Rendering icon"
ICONSET="build/Kvill.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/Kvill.icns"
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
    --entitlements Resources/Kvill.entitlements "$APP"
fi

echo "==> Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$(cd "$APP" && pwd)"

# A running copy keeps the code it launched with, so rebuilding under it changes
# nothing on screen. If Kvill was already open, it is restarted onto the new
# build. The quit goes through AppleScript rather than a kill so that documents
# are given the chance to save; if something is holding it up, the restart is
# skipped and said so rather than forced.
if pgrep -f "$(cd "$APP" && pwd)/Contents/MacOS/Kvill" > /dev/null 2>&1; then
  echo "==> Restarting the running copy"
  osascript -e 'quit app "Kvill"' > /dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    pgrep -f "$(cd "$APP" && pwd)/Contents/MacOS/Kvill" > /dev/null 2>&1 || break
    sleep 0.25
  done

  if pgrep -f "$(cd "$APP" && pwd)/Contents/MacOS/Kvill" > /dev/null 2>&1; then
    echo "    Kvill did not quit, most likely an unsaved document is asking."
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
