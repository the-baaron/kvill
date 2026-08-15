#!/bin/bash
# Sets up everything needed to record the App Review demo video, checks that
# macOS will actually let you record, and prints the shot list.
#
#   ./store/demo-setup.sh
#
# It does not record for you. Recording needs Screen Recording permission for
# whichever app runs the recorder, and driving the editor from a script needs
# Accessibility permission on top of that. Both are per-app grants a human has
# to make in System Settings, so the recording step is yours.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Kvill.app"
DEMO="$HOME/Desktop/Kvill Demo"
OUT="$HOME/Desktop/kvill-demo.mov"

bold=$'\033[1m'; off=$'\033[0m'; red=$'\033[1;31m'; green=$'\033[1;32m'

# --- Can this machine record at all? ----------------------------------------
probe=$(mktemp -t kvill-probe).png
if screencapture -x "$probe" 2>/dev/null && [ -s "$probe" ]; then
  echo "${green}✓${off} Screen Recording is granted."
  recording_ok=yes
else
  echo "${red}✗${off} Screen Recording is NOT granted to this terminal."
  echo "  System Settings › Privacy & Security › Screen & System Audio Recording"
  echo "  Turn it on for your terminal, then quit and reopen the terminal."
  recording_ok=no
fi
rm -f "$probe"

# Counting processes works without the grant, so it is not a test of anything.
# Reading a window's name is refused without it, which is the thing that matters.
if osascript -e \
  'tell application "System Events" to get name of first window of (first process whose frontmost is true)' \
  >/dev/null 2>&1; then
  echo "${green}✓${off} Accessibility is granted, so the run can be scripted if you want."
else
  echo "  (Accessibility is not granted. Not needed if you drive the demo by hand.)"
fi

# --- The folder the video opens ---------------------------------------------
rm -rf "$DEMO"
mkdir -p "$DEMO/Drafts" "$DEMO/Reference"

cat > "$DEMO/Read me first.md" <<'MD'
# Kvill

A Markdown editor for the file you want to change one line in. One file, one window, and nothing to set up first.

## What you are looking at

The `#` above sits out in the **left margin**, dimmed, instead of in the text. Put the cursor on any line and its Markdown comes back exactly as it was typed. Move away and it fades again. Nothing is added to or removed from the file.

> [!NOTE]
> Press `/` on an empty line for the insert menu. Press `Cmd .` to hide every piece of interface, and again to bring it back.

## Everything GitHub supports

- [x] Task lists, with checkboxes you can click
- [ ] Footnotes, callouts, front matter, definition lists
- [ ] Tables that square themselves up when you leave them

| Do this     | Press   |
| ----------- | ------- |
| Insert menu | /       |
| Bold        | Cmd B   |
| Open folder | Shift Cmd O |

```swift
// Code keeps its own panel and its own face.
func greet(_ name: String) -> String {
    return "Hello, \(name)"
}
```

![The picture beside this file](picture.png)
MD

cat > "$DEMO/Drafts/Release notes.md" <<'MD'
# Release notes

What changed, in the order it changed.

- Open a folder and its Markdown shows down the side
- Images stored beside a document load
- Tables square themselves up on save
MD

cat > "$DEMO/Reference/Shortcuts.md" <<'MD'
# Shortcuts

`Cmd B` bold, `Cmd I` italic, `Cmd K` link, `Cmd 1` to `Cmd 6` headings.
`Shift Cmd F` focus mode. `Ctrl Cmd ]` next colour scheme.
MD

# A picture beside the document, so the video can show it loading.
if [ -x "$APP/Contents/MacOS/Kvill" ]; then
  printf '# A picture\n\nDrawn by the app itself.\n' > /tmp/kvill-pic.md
  "$APP/Contents/MacOS/Kvill" --render /tmp/kvill-pic.md "$DEMO/picture.png" \
    --theme sepia --geometry 600x260 --scale 2 >/dev/null 2>&1 || true
  rm -f /tmp/kvill-pic.md
fi

echo
echo "${bold}Demo folder:${off} $DEMO"
ls -1 "$DEMO"

# --- The shot list ------------------------------------------------------------
cat <<EOF

${bold}Shot list${off}  (aim for 60 to 90 seconds, no narration needed)

  1. Finder, showing the demo folder. Double-click ${bold}Read me first.md${off}.
     This answers the usual complaint first: the app opens a real document
     with real content, immediately.

  2. Click into a heading. The Markdown appears in the margin. Click away.
     Do this twice, slowly. It is the thing the app is for.

  3. Click a checkbox in the task list. It ticks.

  4. Put the cursor on an empty line, press ${bold}/${off}, type "tab",
     press Return. A table is inserted. Type in two cells.

  5. Press ${bold}Ctrl Cmd ]${off} two or three times to change colour scheme,
     then ${bold}Cmd +${off} once to change text size.

  6. ${bold}File › Open Folder…${off}, choose the demo folder, click
     ${bold}Release notes${off} in the sidebar, then click back.

  7. Scroll to the bottom so the image is on screen and loads.

  8. Press ${bold}Cmd S${off}. The toast says the file is already saved.

  9. Move the pointer to the top right corner so the chrome springs open,
     and open one of the panels. Then press ${bold}Cmd .${off} to hide all
     interface and again to bring it back.

${bold}Recording${off}
EOF

if [ "$recording_ok" = yes ]; then
  cat <<EOF
  screencapture -v -V 95 "$OUT"

  Stops on its own after 95 seconds, or press Ctrl-C. Writes $OUT
EOF
else
  cat <<EOF
  Grant Screen Recording first (above), or use QuickTime Player:
  File › New Screen Recording, record the screen, then File › Save.
EOF
fi

cat <<EOF

Then attach the file to your reply in App Store Connect ›
App Review › Resolution Center.
EOF
