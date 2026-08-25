#!/bin/bash
# Builds the pictures the marketing site uses, from the app itself.
#
#   ./store/make-site-assets.sh [destination]
#
# Default destination is ../baars.design/src/data/apps/kvill/images.
#
# These are not the App Store screenshots. Those are posters: a window composed
# on a coloured field with a headline set beside it, sized 2880x1800 because
# Apple asks for that. A web page wants the opposite, a photograph of the real
# window with nothing added and nothing around it, at a weight a page can carry.
# Dropping the store shots straight in came to 9.5MB for three images.
#
# Photographed rather than drawn, through store/capture-window.sh, because the
# chrome is glass and glass renders as nothing off screen. What is on this page
# is what the app looks like.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-../baars.design/src/data/apps/kvill/images}"
APP="build/Kvill.app"
NOTES="$PWD/store/notes"

[ -x "$APP/Contents/MacOS/Kvill" ] || { echo "No build at $APP. Run QUILL_SANDBOX=0 ./build.sh first." >&2; exit 1; }
[ -d "$OUT" ] || { echo "No destination at $OUT." >&2; exit 1; }
command -v cwebp > /dev/null || { echo "cwebp is missing: brew install webp" >&2; exit 1; }

# The sandbox refuses a path handed to the app on the command line, and a
# refusal here looks exactly like a window that came up empty. package.sh
# --upload leaves the build signed for distribution, so this is worth checking
# every time rather than only after a change.
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox; then
  echo "$APP is sandboxed; it cannot open the notes folder." >&2
  echo "Run QUILL_SANDBOX=0 ./build.sh first." >&2
  exit 1
fi

WORK="$(mktemp -d -t kvill-site)"
trap 'rm -rf "$WORK"' EXIT

# shot <name> <theme> <document>
shot() {
  ./store/capture-window.sh "$WORK/$1.png" "$NOTES" "$2" "$NOTES/$3" > /dev/null
  # Two widths, so a retina screen gets the sharp one and nobody else pays for
  # it. 1200 across is wider than the column a marketing page gives a picture.
  sips -Z 2400 "$WORK/$1.png" --out "$WORK/$1-2x.png" > /dev/null
  sips -Z 1200 "$WORK/$1.png" --out "$WORK/$1-1x.png" > /dev/null
  # WebP, because these are mostly flat colour and small text. The hero came to
  # 1.9MB as a PNG and 139KB as WebP at quality 88, with the text still sharp.
  # Three pictures as PNG were 6.9MB, which is not a page anyone should be sent.
  cwebp -quiet -q 88 "$WORK/$1-2x.png" -o "$OUT/$1@2x.webp"
  cwebp -quiet -q 88 "$WORK/$1-1x.png" -o "$OUT/$1@1x.webp"
  echo "  $1  $(du -h "$OUT/$1@2x.webp" | cut -f1) @2x, $(du -h "$OUT/$1@1x.webp" | cut -f1) @1x"
}

echo "==> Photographing the app"
shot hero   paper "Launch checklist.md"
shot dark   ink   "Carbonara.md"
shot narrow sepia "Iceland.md"

echo "==> Wrote to $OUT"
du -sh "$OUT"
