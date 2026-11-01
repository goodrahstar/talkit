#!/bin/bash
# Triggers a menu action through the app's URL handler and waits for it to finish.
# Usage: drive.sh on|off|parakeet|groq
set -euo pipefail
marker="$HOME/parakeet-server/menubar/last-action.txt"
rm -f "$marker"
open "parakeetswitch://$1"
for _ in $(seq 1 120); do
  if [ -f "$marker" ]; then cat "$marker"; grep -q "^$1 exit=0 " "$marker"; exit $?; fi
  sleep 1
done
echo "timed out waiting for app action $1" >&2
exit 1
