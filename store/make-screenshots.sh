#!/bin/bash
# Regenerates the App Store screenshots from the real editor.
#
# The page is rendered by the app itself, so what the store shows is what the
# app draws. The window around it is composed afterwards, because the real
# chrome is glass and glass renders as nothing off screen.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Signet.app/Contents/MacOS/Signet"
[ -x "$APP" ] || { echo "Build first: QUILL_SANDBOX=0 ./build.sh" >&2; exit 1; }

# Must match the window sizes in scripts/make-shot.swift.
centre_size="1010x640"
bleed_size="1010x708"

shot() {  # number theme typography layout light|dark headline subline
  local geometry="$bleed_size"
  [ "$4" = "centre" ] && geometry="$centre_size"
  "$APP" --render "store/shot-$1.md" "store/page-$1.png" \
    --theme "$2" --typography "$3" --geometry "$geometry" --scale 2 > /dev/null
  swift scripts/make-shot.swift "store/screenshots/$1.png" "store/page-$1.png" \
    "$4" "$5" "$6" "$7" > /dev/null
  printf "  %s.png  %-7s %-9s %s\n" "$1" "$2" "$3" "$4"
}

mkdir -p store/screenshots
rm -f store/screenshots/*.png store/page-*.png

echo "==> Composing"
shot 1 paper editorial centre light \
  "Markdown that stays out of the way" \
  "Syntax hangs in the margin, so your words keep one clean edge."
shot 2 ink editorial right dark \
  "Written to be read" \
  "Eight palettes. Five typefaces. Each with the line height and spacing that suit it."
shot 3 sepia editorial left light \
  "Yours, and only yours" \
  "No network, no account, no tracking. Free, and open source."

rm -f store/page-*.png
echo
sips -g pixelWidth -g pixelHeight store/screenshots/1.png 2>/dev/null | tail -2
