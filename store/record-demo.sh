#!/bin/bash
# Records the App Review demo video without anyone touching the keyboard.
#
#   ./store/demo-setup.sh      builds the folder this expects
#   ./store/record-demo.sh     records ~80 seconds to ~/Desktop/kvill-demo.mov
#
# Needs two permissions, both granted to whichever app runs this (iTerm here),
# in System Settings › Privacy & Security:
#
#   Screen & System Audio Recording   to capture
#   Accessibility                     to drive the editor
#
# macOS only applies either one after the app is restarted.
#
# Everything is driven from the keyboard. Clicking at coordinates would depend
# on where the window landed and on the display size, and would break silently
# by typing into the wrong place; every step here is a key the app itself
# defines.
set -euo pipefail
cd "$(dirname "$0")/.."

DEMO="$HOME/Desktop/Kvill Demo"
DOC="$DEMO/Read me first.md"
OUT="$HOME/Desktop/kvill-demo.mov"
APP="$PWD/build/Kvill.app"

[ -f "$DOC" ] || { echo "Run ./store/demo-setup.sh first: $DOC is missing." >&2; exit 1; }
[ -d "$APP" ] || { echo "No build at $APP. Run ./build.sh first." >&2; exit 1; }

probe=$(mktemp -t kvill-probe).png
if ! screencapture -x "$probe" 2>/dev/null || [ ! -s "$probe" ]; then
  rm -f "$probe"
  echo "Screen Recording is not granted. System Settings › Privacy & Security ›" >&2
  echo "Screen & System Audio Recording, switch on this terminal, restart it." >&2
  exit 1
fi
rm -f "$probe"

if ! osascript -e \
  'tell application "System Events" to get name of first window of (first process whose frontmost is true)' \
  >/dev/null 2>&1; then
  echo "Accessibility is not granted. System Settings › Privacy & Security ›" >&2
  echo "Accessibility, switch on this terminal, restart it." >&2
  exit 1
fi

# Apple asked for a recording that begins with the app launching, so it must
# not already be running.
osascript -e 'quit app "Kvill"' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do pgrep -x Kvill >/dev/null || break; sleep 0.25; done

rm -f "$OUT"
echo "Recording to $OUT"
screencapture -v -V 82 "$OUT" &
RECORDER=$!
sleep 3

step() { osascript -e "$1" >/dev/null 2>&1 || true; sleep "${2:-1}"; }
key()  { step "tell application \"System Events\" to keystroke $1" "${2:-1}"; }

# 1. Launch by opening a document, which is how anyone actually starts.
open -a "$APP" "$DOC"
sleep 5
step 'tell application "Kvill" to activate' 2

# 2. Walk the caret down the opening lines. Each line reveals its own syntax in
#    the margin as the caret enters it, which is the whole idea of the app.
step 'tell application "System Events" to key code 126 using {command down}' 1
for _ in 1 2 3 4 5 6 7 8; do
  step 'tell application "System Events" to key code 125' 0.7
done

# 3. Type a heading and a line under it, so the video shows editing, not just
#    scrolling through something already written.
step 'tell application "System Events" to key code 125 using {command down}' 1
key '"'$'\n''"' 1
key '"## Written just now"' 1
key '"'$'\n''"' 1
key '"Typed into the document while this was being recorded."' 2

# 4. The insert menu.
key '"'$'\n''"' 1
key '"/"' 2
key '"table"' 2
key '"'$'\n''"' 2

# 5. Colour scheme and text size, both app-wide settings.
step 'tell application "System Events" to keystroke "]" using {control down, command down}' 2
step 'tell application "System Events" to keystroke "]" using {control down, command down}' 2
step 'tell application "System Events" to keystroke "+" using {command down}' 2

# 6. Saving. The file has been saving itself the whole time; this shows it.
step 'tell application "System Events" to keystroke "s" using {command down}' 3

# 7. Hide every piece of interface, then bring it back.
step 'tell application "System Events" to keystroke "." using {command down}' 3
step 'tell application "System Events" to keystroke "." using {command down}' 2

wait $RECORDER || true
echo
if [ -s "$OUT" ]; then
  echo "Wrote $OUT"
  echo "Watch it before sending. If a step went astray it will be obvious,"
  echo "and the file is safe to delete and record again."
else
  echo "Nothing was written. The recorder was stopped or refused." >&2
  exit 1
fi
