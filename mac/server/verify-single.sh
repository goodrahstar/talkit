#!/bin/bash
# Checks that only the requested model is ever loaded and nothing runs a second model.
set -u
f=$(ls -t "$HOME/Library/Application Support/FreeFlow/audio/"*.wav | head -1)
api=http://127.0.0.1:5092
loaded() { curl -sf $api/health | /usr/bin/python3 -c 'import json,sys;print(",".join(json.load(sys.stdin)["loaded"]))'; }
before=$(grep -c 'transcribed' "$HOME/parakeet-server/server.log")
for m in parakeet-ultra parakeet-v3 parakeet-ultra; do
  t=$(curl -sf -F "file=@$f" -F model=$m $api/v1/audio/transcriptions | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["text"])') || { echo "$m failed"; exit 1; }
  [ $(echo "$t" | wc -w) -ge 2 ] || { echo "$m empty"; exit 1; }
  sleep 2
  l=$(loaded); [ "$l" = "$m" ] || { echo "after $m loaded=$l"; exit 1; }
  echo "$m only loaded | $t" | cut -c1-110
done
after=$(grep -c 'transcribed' "$HOME/parakeet-server/server.log")
[ $((after - before)) -eq 3 ] || { echo "expected 3 transcriptions, got $((after - before))"; exit 1; }
echo SINGLE_MODEL_OK
