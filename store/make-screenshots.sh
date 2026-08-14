#!/bin/bash
# Regenerates the App Store screenshots from the real editor.
#
# The page is rendered by the app itself, so what the store shows is what the
# app draws. The window around it is composed afterwards, because the real
# chrome is glass and glass renders as nothing off screen.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Kvill.app/Contents/MacOS/Kvill"
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
  "Straight to the page" \
  "No project to open, nothing to index. The cursor is already waiting."
shot 2 ink editorial right dark \
  "All of Markdown, none of the weight" \
  "Tables, callouts, code, footnotes. No sidebar, no inspector, no workspace."
shot 3 sepia editorial left light \
  "Yours, and only yours" \
  "No network, no account, no tracking. Free, and open source."
shot 4 nord editorial centre dark \
  "Set properly, not just styled" \
  "Eight palettes and five typefaces, each with the spacing that suits it."
shot 5 contrast-light grotesk right light \
  "Everything, without the mouse" \
  "Press / and the whole of Markdown is three keystrokes away."

rm -f store/page-*.png
echo
sips -g pixelWidth -g pixelHeight store/screenshots/1.png 2>/dev/null | tail -2
