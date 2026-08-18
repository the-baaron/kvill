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
  # Beside a sidebar the page is narrower, so it is rendered narrower rather
  # than rendered wide and squeezed. Scaling a page sets its text at a size the
  # app never uses, which is the one thing a screenshot of a typography app
  # must not do.
  # 935 wide on the canvas, less the 232 the sidebar takes.
  [ "${8:-}" = "sidebar" ] && geometry="703x708"
  "$APP" --render "store/shot-$1.md" "store/page-$1.png" \
    --theme "$2" --typography "$3" --geometry "$geometry" --scale 2 > /dev/null
  # An empty array expands to an error under set -u on the bash that ships with
  # macOS, so the sidebar is passed as a plain argument or not at all.
  if [ "${8:-}" = "sidebar" ]; then
    # The real tree view, rendered from a real folder, not a drawing of one.
    # Sized to the space it will occupy, minus the strip the traffic lights
    # sit in, so nothing is stretched to fit afterwards.
    "$APP" --tree "store/notes" "store/tree-$1.png" --theme "$2" --size 232x664 > /dev/null
    swift scripts/make-shot.swift "store/screenshots/$1.png" "store/page-$1.png" \
      "$4" "$5" "$6" "$7" "store/tree-$1.png" > /dev/null
  else
    swift scripts/make-shot.swift "store/screenshots/$1.png" "store/page-$1.png" \
      "$4" "$5" "$6" "$7" > /dev/null
  fi
  printf "  %s.png  %-7s %-9s %-7s %s\n" "$1" "$2" "$3" "$4" "${8:-}"
}

mkdir -p store/screenshots
rm -f store/screenshots/*.png store/page-*.png store/tree-*.png

echo "==> Composing"
shot 1 paper editorial centre light \
  "Opens faster than you can say Markdown" \
  "Nine hundredths of a second, and nothing deferred to make that true."
shot 2 ink editorial right dark \
  "A folder of notes, in one window" \
  "Open a folder and its files sit down the side. Click through them in place." \
  sidebar
shot 3 sepia editorial left light \
  "Just edit local files" \
  "Plain Markdown on your own disk. Nothing to sign into, nothing to import."
shot 4 nord editorial centre dark \
  "Six colour schemes and five typefaces" \
  "Each with the line height, measure and spacing that suit it."
shot 5 contrast-light grotesk right light \
  "Every command has a key" \
  "Press / for the insert menu. Bold, links and headings are one chord away."

rm -f store/page-*.png store/tree-*.png
echo
sips -g pixelWidth -g pixelHeight store/screenshots/1.png 2>/dev/null | tail -2
