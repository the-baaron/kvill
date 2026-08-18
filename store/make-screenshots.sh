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

shot() {  # number theme typography layout light|dark headline subline [sidebar]
  local geometry="$bleed_size"
  [ "$4" = "centre" ] && geometry="$centre_size"
  [ "$4" = "small" ] && geometry="620x600"
  # Beside a sidebar the page is narrower, so it is rendered narrower rather
  # than rendered wide and squeezed. Scaling a page sets its text at a size the
  # app never uses, which is the one thing a screenshot of a typography app
  # must not do.
  "$APP" --render "store/shot-$1.md" "store/page-$1.png" \
    --theme "$2" --typography "$3" --geometry "$geometry" --scale 2 > /dev/null
  if [ "${8:-}" = "photo" ]; then
    # A photograph of the real window, which is the only way to show the
    # sidebar without a seam and the only way to show glass chrome at all.
    ./store/capture-window.sh "store/window-$1.png" "$PWD/store/notes" "$2" \
      "$PWD/store/notes/Launch checklist.md" > /dev/null
    SHOT_THEME="$2" SHOT_WINDOW="store/window-$1.png" \
      swift scripts/make-shot.swift "store/screenshots/$1.png" "store/page-$1.png" \
      "$4" "$5" "$6" "$7" > /dev/null
  else
    SHOT_THEME="$2" swift scripts/make-shot.swift "store/screenshots/$1.png" "store/page-$1.png" \
      "$4" "$5" "$6" "$7" > /dev/null
  fi
  printf "  %s.png  %-7s %-9s %-7s %s\n" "$1" "$2" "$3" "$4" "${8:-}"
}

mkdir -p store/screenshots
rm -f store/screenshots/*.png store/page-*.png store/window-*.png

echo "==> Composing"
shot 1 paper editorial centre light \
  "Opens faster than you can say Markdown" \
  "Nine hundredths of a second, and nothing deferred to make that true."
shot 2 ink editorial right dark \
  "A folder of notes, in one window" \
  "Open a folder and its files sit down the side. Click through them in place." \
  photo
shot 3 sepia editorial small light \
  "Just edit local files" \
  "Plain Markdown on your own disk. Nothing to sign into, nothing to import."
shot 4 nord editorial centre dark \
  "Six colour schemes and five typefaces" \
  "Each with the line height, measure and spacing that suit it."
shot 5 contrast-light grotesk right light \
  "Every command has a key" \
  "Press / for the insert menu. Bold, links and headings are one chord away."

rm -f store/page-*.png store/window-*.png
echo
sips -g pixelWidth -g pixelHeight store/screenshots/1.png 2>/dev/null | tail -2
