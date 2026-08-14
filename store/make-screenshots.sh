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

shot() {  # number theme typography light|dark headline subline
  "$APP" --render "store/shot-$1.md" "store/page-$1.png" \
    --theme "$2" --typography "$3" --geometry 1000x596 --scale 2 --offset 104 > /dev/null
  swift scripts/make-shot.swift "store/screenshots/$1.png" "store/page-$1.png" \
    "$5" "$6" "$4" > /dev/null
  echo "  $1.png  $2/$3"
}

mkdir -p store/screenshots
rm -f store/screenshots/*.png store/page-*.png

echo "==> Composing"
shot 1 paper editorial light \
  "Markdown that stays out of the way" \
  "Syntax hangs in the margin. Your words keep one clean edge."
shot 2 ink editorial dark \
  "Written to be read" \
  "Eight palettes and five typefaces, all set properly."
shot 3 sepia editorial light \
  "Yours, and only yours" \
  "No network, no account, no tracking. Free, and open source."

rm -f store/page-*.png
echo
sips -g pixelWidth -g pixelHeight store/screenshots/1.png 2>/dev/null | tail -2
