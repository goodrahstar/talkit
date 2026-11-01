#!/bin/bash
# Runs a throwaway server on :5095 with a 20s idle unload; checks unload then reload.
set -u
cd "$(dirname "$0")"
T=$(mktemp -d)
PARAKEET_PORT=5095 PARAKEET_IDLE_UNLOAD_SECONDS=20 .build/release/ParakeetServer >$T/s.log 2>&1 &
srv=$!; trap 'kill $srv 2>/dev/null; rm -rf $T' EXIT
for _ in $(seq 20); do curl -sf localhost:5095/health >/dev/null && break; sleep 0.5; done
f=$(ls -t "$HOME/Library/Application Support/FreeFlow/audio/"*.wav | head -1)
curl -sf -o /dev/null -F "file=@$f" -F model=parakeet-ultra localhost:5095/v1/audio/transcriptions || { echo "request failed"; exit 1; }
sleep 3; curl -s localhost:5095/health | grep -q '"loaded":\["parakeet-ultra"\]' || { echo "not loaded: $(curl -s localhost:5095/health)"; exit 1; }
sleep 45; curl -s localhost:5095/health | grep -q '"loaded":\[\]' || { echo "not unloaded: $(curl -s localhost:5095/health)"; exit 1; }
start=$(date +%s)
curl -sf -o /dev/null -F "file=@$f" -F model=parakeet-ultra localhost:5095/v1/audio/transcriptions || { echo "reload failed"; exit 1; }
echo "reload_seconds<=$(( $(date +%s) - start + 1 ))"; grep -E 'loaded|unloaded' $T/s.log
echo IDLE_UNLOAD_OK
