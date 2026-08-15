#!/bin/bash
# Records the App Review demo video.
#
#   ./store/demo-setup.sh      builds the folder this expects
#   ./store/record-demo.sh     records to ~/Desktop/kvill-demo.mov
#
# Only Screen Recording is needed. The app drives itself through `--demo`, so
# there are no synthesised keystrokes and no Accessibility permission. See
# Sources/Kvill/App/DemoDriver.swift for what it does and why.
set -euo pipefail
cd "$(dirname "$0")/.."

DEMO="$HOME/Kvill Demo"
DOC="$DEMO/Read me first.md"
PRISTINE="$DEMO/.pristine.md"
OUT="$HOME/Desktop/kvill-demo.mov"
APP="$PWD/build/Kvill.app"
LENGTH=75

[ -f "$DOC" ] || { echo "Run ./store/demo-setup.sh first: $DOC is missing." >&2; exit 1; }
[ -d "$APP" ] || { echo "No build at $APP. Run ./build.sh first." >&2; exit 1; }

probe=$(mktemp -t kvill-probe).png
if ! screencapture -x "$probe" 2>/dev/null || [ ! -s "$probe" ]; then
  rm -f "$probe"
  echo "Screen Recording is not granted, or the display is asleep." >&2
  echo "System Settings › Privacy & Security › Screen & System Audio Recording." >&2
  exit 1
fi
rm -f "$probe"

# The demo types into the document and the document saves itself, so a second
# run would start from the first run's leftovers. The first run keeps a copy.
if [ -f "$PRISTINE" ]; then
  cp "$PRISTINE" "$DOC"
  echo "Restored the document from before the last run."
else
  cp "$DOC" "$PRISTINE"
fi

# Not through AppleScript. `quit app` launches the app when it is not running,
# and asking to control another app raises its own permission dialogue, which
# then sits in the middle of the recording.
pkill -x Kvill 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -x Kvill >/dev/null || break; sleep 0.25; done

# The display going to sleep mid-take produces a recording of nothing at all,
# which looks exactly like a recording that failed to start.
caffeinate -u -d -t $((LENGTH + 30)) &
CAFFEINE=$!
sleep 2

rm -f "$OUT"
echo "Recording ${LENGTH}s to $OUT"
screencapture -v -V "$LENGTH" "$OUT" &
RECORDER=$!
sleep 2

open -a "$APP" "$DOC" --args --demo

wait $RECORDER || true
kill $CAFFEINE 2>/dev/null || true
pkill -x Kvill 2>/dev/null || true

if [ -s "$OUT" ]; then
  echo "Wrote $OUT  ($(ls -l "$OUT" | awk '{printf "%.1f MB", $5/1048576}'))"
  echo "Watch it before sending. The document is restored automatically, so"
  echo "running this again is safe."
else
  echo "Nothing was written." >&2
  exit 1
fi
