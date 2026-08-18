#!/bin/bash
# Photographs the real app window, sidebar and all.
#
#   ./store/capture-window.sh out.png folder theme [document.md]
#
# The window in the App Store screenshots used to be drawn: a rounded rectangle
# with traffic lights painted on and a rendered page inside it. That works for a
# page and falls apart for anything else. The sidebar had to be rendered
# separately and composed back, which put a seam where the app has none and cut
# the top off it, three times. Glass chrome does not render off screen at all,
# so no drawn window could ever show the options panel or the insert menu.
#
# This takes a picture of the app.
set -euo pipefail
cd "$(dirname "$0")/.."

out="$1"; folder="$2"; theme="$3"; document="${4:-}"
APP="$PWD/build/Kvill.app"
[ -x "$APP/Contents/MacOS/Kvill" ] || { echo "Build first" >&2; exit 1; }

# The palette is a user setting, so it is set, used, and put back. A screenshot
# run must not leave someone's editor in a different colour scheme.
DOMAIN="$HOME/Library/Preferences/design.baars.Signet"
previous="$(defaults read "$DOMAIN" kvill.palette 2>/dev/null || echo '')"
restore() {
  if [ -n "$previous" ]; then defaults write "$DOMAIN" kvill.palette -string "$previous"
  else defaults delete "$DOMAIN" kvill.palette 2>/dev/null || true; fi
  pkill -x Kvill 2>/dev/null || true
}
trap restore EXIT

# Wake the display and hold it awake. A sleeping display makes screencapture
# fail on a window or a region and return solid black for the whole screen,
# which reads as a permission problem and is not one. The demo recorder in this
# repository already knew that and this did not.
caffeinate -u -t 90 &
sleep 2

pkill -x Kvill 2>/dev/null || true
sleep 1
defaults write "$DOMAIN" kvill.palette -string "$theme"
defaults write "$DOMAIN" kvill.followSystemAppearance -bool false

# Document first, then the folder. Opening a folder attaches its tree to the
# window that is already open, so this ends up with the chosen document showing
# and the sidebar beside it. The other order opens the folder's first file, and
# opening a document afterwards puts it in a window of its own with no sidebar,
# which is the app working correctly and a photograph missing the point.
# Waited for rather than slept through. Fixed sleeps failed the moment the
# machine was busy, and a capture of a window that is not up yet fails with
# "could not create image from window" after the whole run has gone by.
await() {  # what, seconds
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    [ -n "$(swift store/window-id.swift)" ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

if [ -n "$document" ]; then
  open -a "$APP" "$document"
  await window 20 || { echo "the document never opened a window" >&2; exit 1; }
  sleep 2
  open -a "$APP" "$folder"
else
  open -a "$APP" "$folder"
  await window 20 || { echo "the folder never opened a window" >&2; exit 1; }
fi
# The sidebar animates in, and the tree lays out after that.
sleep 3

id="$(swift store/window-id.swift)"
[ -n "$id" ] || { echo "no Kvill window to photograph" >&2; exit 1; }

# -o leaves the shadow out, so the compositor can draw its own and the window
# sits on the canvas rather than carrying a rectangle of someone's desktop.
# Re-checked rather than trusted: the id is read, then the window is asked for.
[ "$id" = "$(swift store/window-id.swift)" ] || id="$(swift store/window-id.swift)"
screencapture -x -o -l "$id" "$out"
[ -s "$out" ] || { echo "screencapture produced nothing for window $id" >&2; exit 1; }
echo "photographed window $id into $out"
