#!/bin/bash
# Set up local Parakeet speech-to-text on a Mac: server (port 5092), ffstt command, menu bar switch.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/parakeet-server"

mkdir -p "$DEST/ane" "$DEST/menubar" "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
rsync -a --exclude .build "$HERE/server/" "$DEST/ane/"
rsync -a "$HERE/menubar/" "$DEST/menubar/"
(cd "$DEST/ane" && swift build -c release)
"$DEST/menubar/build.sh"
install -m 755 "$HERE/bin/ffstt" "$HOME/.local/bin/ffstt"

for label in com.rahul.parakeet-server com.rahul.parakeet-switch; do
  sed "s#/Users/rahulkumar#$HOME#g" "$HERE/launchd/$label.plist" > "$HOME/Library/LaunchAgents/$label.plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist"
done
echo "Done. Server on http://127.0.0.1:5092/v1 (first request downloads the model). Try: ffstt status"
