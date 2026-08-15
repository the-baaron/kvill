#!/bin/bash
# Sets up everything needed to record the App Review demo video, checks that
# macOS will actually let you record, and prints the shot list.
#
#   ./store/demo-setup.sh
#
# Recording itself is ./store/record-demo.sh. That needs Screen Recording
# permission, which only a human can grant, so this checks for it and says so
# rather than failing in the middle of a take.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Kvill.app"
DEMO="$HOME/Kvill Demo"
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
# In the home folder rather than on the Desktop. The Desktop is one of the
# folders macOS protects, so opening a document there raises a permission
# dialogue that blocks the window until a human clicks it, every launch, which
# makes an unattended recording impossible.
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

# --- What to do with it ------------------------------------------------------
cat <<EOF

${bold}Recording it yourself${off}, which is worth doing: an automated take has no
pointer moving and no clicks, and reads as synthetic.

  0. Quit Kvill. Apple asked for a recording that begins at launch.
  1. Double-click ${bold}Read me first.md${off} in the demo folder.
  2. Click into a heading, then away. The Markdown appears in the margin
     and fades. Do it twice, slowly. It is what the app is for.
  3. Click a checkbox in the task list.
  4. On an empty line press ${bold}/${off}, type "table", press Return, type in
     two cells.
  5. ${bold}Ctrl Cmd ]${off} twice for colour schemes, ${bold}Cmd +${off} once for size.
  6. ${bold}File › Open Folder…${off}, pick this folder, click ${bold}Release notes${off}
     in the sidebar, then click back. This is the only way the sidebar
     gets shown, and it is a real feature worth showing.
  7. Scroll to the image at the bottom.
  8. ${bold}Cmd S${off} for the toast, then ${bold}Cmd .${off} to hide the interface and
     again to bring it back.

  screencapture -v -V 95 ~/Desktop/kvill-demo.mov

${bold}Or automated${off}, with no pointer and no clicks:

  ./store/record-demo.sh

The app drives itself: it opens the document, walks the caret down the
opening lines so each reveals its syntax in the margin, types a heading and
a sentence, opens the insert menu and inserts a table, changes the colour
scheme and the text size, saves, and hides and restores the interface. See
Sources/Kvill/App/DemoDriver.swift.

${bold}Samples${off}, which Apple also asked for

  cd "\$HOME" && zip -r ~/Desktop/kvill-samples.zip "Kvill Demo" -x "*/.pristine.md" >/dev/null

Then attach the recording and the zip to your reply in App Store Connect ›
App Review › Resolution Center. The written answers are already in App
Review Information.
EOF
