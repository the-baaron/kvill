#!/bin/bash
# Builds every image the baars.design case study uses, from the app itself.
#
#   ./store/make-portfolio-assets.sh [destination]
#
# Default destination is ../baars.design/src/data/work/kvill/images.
#
# The pages are rendered by Kvill, so what the case study shows is what the app
# draws. The window around them is composed by scripts/make-portfolio.swift for
# the same reason the App Store shots are: the real chrome is glass, and glass
# renders as nothing off screen.
#
# Two things about the portfolio decide the geometry here, and both were learnt
# by getting them wrong:
#
#   The tile is cropped. A work tile is 300x458 and fills itself with
#   `background-size: cover`, so it keeps the middle 44.5% of the width of a
#   1448x984 thumbnail. The first motif was drawn across the full canvas and
#   every marker landed in the discarded part. --band 0.445 composes inside what
#   survives.
#
#   The header carries text. The title and intro are set over it as a section
#   background. A flat wash strong enough to keep them readable flattens the
#   picture with them, so it is graded instead: solid aqua where the words are,
#   thinning to almost nothing below them.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-../baars.design/src/data/work/kvill/images}"
APP="build/Kvill.app/Contents/MacOS/Kvill"
WORK="$(mktemp -d -t kvill-portfolio)"
trap 'rm -rf "$WORK"' EXIT

[ -x "$APP" ] || { echo "No build at $APP. Run QUILL_SANDBOX=0 ./build.sh first." >&2; exit 1; }
[ -d "$OUT" ] || { echo "No destination at $OUT." >&2; exit 1; }

# The sandbox refuses a path handed to the app on the command line, and a
# refusal here looks exactly like a render that came out empty.
if codesign -d --entitlements - "build/Kvill.app" 2>/dev/null | grep -q app-sandbox; then
  echo "build/Kvill.app is sandboxed; --render cannot read these files." >&2
  echo "Rebuild with QUILL_SANDBOX=0 ./build.sh" >&2
  exit 1
fi

# make-portfolio.swift insets the card by 11.5% of the width each side and gives
# a sidebar 22% of what is left. A page rendered at any other shape is refused
# rather than squashed, so the numbers are derived here once.
geometry() {          # geometry WIDTH HEIGHT [sidebar]
  awk -v w="$1" -v h="$2" -v side="${3:-0}" 'BEGIN {
    margin = int(w * 0.115 + 0.5)
    card = w - margin * 2
    bar = side ? int(card * 0.22 + 0.5) : 0
    printf "%dx%d\n", card - bar, h
  }'
}

render() {            # render out.md-body out.png theme geometry [typography]
  "$APP" --render "$1" "$2" --theme "$3" --geometry "$4" --scale 2 >/dev/null
}

# --- The pages ---------------------------------------------------------------

cat > "$WORK/header.md" <<'MD'
# Opens faster than you can say Markdown

Double-click to a page you can type on takes about nine hundredths of a second. Nothing is being cleverly deferred either: there is no project to open, no workspace to restore and no index to build.

## The margin

A `#` sits out in the left margin, dimmed and right-aligned, so a top-level heading and a sixth-level one finish on the same column and your prose keeps one straight edge.

> [!NOTE]
> Nothing is inserted into or removed from the file to do it. The characters are still there, kerned to nothing, and they come back the moment the cursor enters that line.
MD

cat > "$WORK/tree.md" <<'MD'
# Release notes

What changed, in the order it changed.

## This week

- Open a folder and its Markdown shows down the side
- Images beside a document load, at last
- Tables square themselves up on save

> The sandbox grants what you chose and nothing else, so choosing the folder is the permission.
MD

cat > "$WORK/dark.md" <<'MD'
## Written to be read

Prose is set on a measure that stays comfortable, in a face chosen for long stretches rather than for screenshots, with the line height and the spacing that go with it.

```swift
// Code keeps its own panel and its own face.
func greet(_ name: String) -> String {
    let count = 42
    return "Hello, \(name) and \(count)"
}
```
MD

cat > "$WORK/keys.md" <<'MD'
## Everything, without the mouse

Press / anywhere and an insert menu opens under the cursor, filtering as you type.

| Do this     | Press   |
| ----------- | ------- |
| Insert menu | /       |
| Bold        | Cmd B   |
| Task list   | Shift 9 |
| Focus mode  | Shift F |
MD

# The folder the sidebar shows. It is drawn from a real one, not mocked up.
DEMO="$WORK/Notes"
mkdir -p "$DEMO/Drafts" "$DEMO/Reference"
for f in "$DEMO/Release notes.md" "$DEMO/Reading list.md" \
         "$DEMO/Drafts/Ideas.md" "$DEMO/Drafts/Standup.md" \
         "$DEMO/Reference/Shortcuts.md"; do
  printf '# %s\n\nA line.\n' "$(basename "${f%.md}")" > "$f"
done

# --- The thumbnail -----------------------------------------------------------
# 1448x984 at 2x, of which the tile shows the middle 44.5% of the width.
swift scripts/make-motif.swift "$WORK/thumbnail.png" 724x492 --band 0.445 --logo-band 0.15
cp "$WORK/thumbnail.png" "$OUT/thumbnail@2x.png"
sips -Z 724 "$WORK/thumbnail.png" --out "$OUT/thumbnail@1x.png" >/dev/null

# --- The header --------------------------------------------------------------
# At a 1440 viewport the section is 848 tall and the image is the bottom 600 of
# it, so the title clears the image entirely and the intro paragraph reaches
# 18% down it. Measured in the browser, not guessed: the first attempt held the
# aqua solid to 46% on an estimate and buried the headline. Solid to 20%, full
# strength from 42%, which puts the H1 in the reveal.
HEADER_PAGE="$(geometry 1440 600)"
render "$WORK/header.md" "$WORK/page-header.png" paper "$HEADER_PAGE"
swift scripts/make-portfolio.swift "$WORK/header.png" 1440x600 light "$WORK/page-header.png" \
  --drop 0.06 --fade D7FCF6 1.0 0.12 0.20 0.42
cp "$WORK/header.png" "$OUT/header@2x.png"
sips -Z 1440 "$WORK/header.png" --out "$OUT/header@1x.png" >/dev/null

# --- The three in the body ---------------------------------------------------
# 940x492, shown by the page as a 490px-tall band at full section width.
BODY_PAGE="$(geometry 940 492)"
BODY_PAGE_SIDEBAR="$(geometry 940 492 sidebar)"

"$APP" --tree "$DEMO" "$WORK/sidebar.png" --theme paper >/dev/null
render "$WORK/tree.md" "$WORK/page-tree.png" paper "$BODY_PAGE_SIDEBAR"
swift scripts/make-portfolio.swift "$WORK/full1.png" 940x492 light \
  "$WORK/page-tree.png" "$WORK/sidebar.png"

render "$WORK/dark.md" "$WORK/page-dark.png" onyx "$BODY_PAGE"
swift scripts/make-portfolio.swift "$WORK/full2.png" 940x492 dark "$WORK/page-dark.png"

render "$WORK/keys.md" "$WORK/page-keys.png" sepia "$BODY_PAGE"
swift scripts/make-portfolio.swift "$WORK/full3.png" 940x492 light "$WORK/page-keys.png"

for n in 1 2 3; do
  cp "$WORK/full$n.png" "$OUT/image_full_$n@2x.png"
  sips -Z 940 "$WORK/full$n.png" --out "$OUT/image_full_$n@1x.png" >/dev/null
done

# --- The wordmark ------------------------------------------------------------
swift scripts/make-logo.swift "$OUT/logo.svg"

# A blank PNG and a drawn one are the same file size to a glance, so say what
# came out rather than reporting success.
echo
for f in "$OUT"/*.png "$OUT"/logo.svg; do
  printf '%-24s %7s bytes  %s\n' "$(basename "$f")" "$(stat -f%z "$f")" \
    "$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')"
done
