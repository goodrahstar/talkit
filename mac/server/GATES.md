# Gates: Neural Engine Parakeet server (v3 + Ultra) replacing the GPU server

OWNS: ~/parakeet-server/**, ~/.local/bin/ffstt, ~/Library/LaunchAgents/com.rahul.parakeet-server.plist, ~/Applications/Parakeet Switch.app/**, ~/.cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v3

Scope: A Swift/FluidAudio server on :5092 serves Parakeet v3 and Ultra on the Neural Engine with only the chosen model loaded, FreeFlow and the menu bar switch between v3, Ultra and Groq, and the GPU/MLX setup is gone.

- [x] G1: Server builds in release mode
  CHECK: swift build -c release --disable-keychain 2>&1 | tail -1
  EXPECT: Build complete!
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=Build complete! (0.23s)

- [x] G2: launchd runs the Swift server and it lists both models
  CHECK: launchctl print gui/$(id -u)/com.rahul.parakeet-server | grep -q 'ane/.build/release/ParakeetServer' && curl -sf http://127.0.0.1:5092/v1/models
  EXPECT: /"parakeet-ultra"[\s\S]*"parakeet-v3"|"parakeet-v3"[\s\S]*"parakeet-ultra"/
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output={"object":"list","data":[{"id":"parakeet-ultra","object":"model","owned_by":"local"},{"id":"parakeet-v3","object":"model","owned_by":"local"}]}

- [x] G3: Only the requested model is loaded and runs; switching models unloads the other and no second model runs
  CHECK: ./verify-single.sh
  EXPECT: SINGLE_MODEL_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=parakeet-ultra only loaded | Very similar to Whisperflow. | SINGLE_MODEL_OK

- [x] G4: Ultra's `<unk>` and double-full-stop artifacts are cleaned (raw text taken from Ultra's real output on the R&D clip, 2026-10-23)
  CHECK: b=.build/release/ParakeetServer; $b --clean 'worked in the R<unk>D, applied R<unk>D, in commercial companies.. it is <unk> fine...' | /usr/bin/python3 -c 'import sys;t=sys.stdin.read().strip();assert t=="worked in the R&D, applied R&D, in commercial companies. it is fine...",t;print("UNK_FIXED",t)'
  EXPECT: UNK_FIXED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=UNK_FIXED worked in the R&D, applied R&D, in commercial companies. it is fine...

- [x] G5: Model unloads after idle and reloads on the next request
  CHECK: ./verify-idle.sh
  EXPECT: IDLE_UNLOAD_OK
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=2026-10-23T17:02:22Z loaded parakeet-ultra in 0.34s | IDLE_UNLOAD_OK

- [x] G6: ffstt switches between ultra, v3 and groq, and off/on stops and starts the server
  CHECK: ffstt=~/.local/bin/ffstt; $ffstt ultra >/dev/null && $ffstt status && defaults read com.zachlatta.freeflow transcription_model && $ffstt v3 >/dev/null && $ffstt status && $ffstt off >/dev/null && sleep 2 && $ffstt status && $ffstt on >/dev/null && sleep 4 && $ffstt ultra >/dev/null && $ffstt status
  EXPECT: /FreeFlow STT: ultra \| Parakeet server: running\s+parakeet-ultra[\s\S]*FreeFlow STT: v3 \| Parakeet server: running[\s\S]*FreeFlow STT: groq \| Parakeet server: stopped[\s\S]*FreeFlow STT: ultra \| Parakeet server: running/
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=FreeFlow STT: groq | Parakeet server: stopped | FreeFlow STT: ultra | Parakeet server: running

- [x] G7: Menu bar app drives Ultra, v3 and Groq
  CHECK: d=../menubar/drive.sh; $d v3 && ~/.local/bin/ffstt status && $d groq && ~/.local/bin/ffstt status && $d ultra && ~/.local/bin/ffstt status
  EXPECT: /FreeFlow STT: v3 \| Parakeet server: running[\s\S]*FreeFlow STT: groq \| Parakeet server: running[\s\S]*FreeFlow STT: ultra \| Parakeet server: running/
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=ultra exit=0 1792774955.819068 | FreeFlow STT: ultra | Parakeet server: running

- [x] G8: GPU setup is gone: MLX model deleted, Python server removed, no Python server process
  CHECK: ! test -e ~/.cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v3 && ! test -e ~/parakeet-server/.venv && ! test -e ~/parakeet-server/server.py && ! pgrep -f 'uvicorn server:app' >/dev/null && echo GPU_REMOVED
  EXPECT: GPU_REMOVED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=GPU_REMOVED

- [x] G9: A real FreeFlow dictation is served by the Neural Engine server (superseded comparison behaviour)
  EVIDENCE: manual 2026-10-23; server.log "parakeet-ultra transcribed 92864 bytes in 0.35s: Testing the Paracat model." and 743764 bytes in 0.47s matching the user's message; compare.log showed both models before single-model change

- [x] G10: Choosing a model in ffstt/menu loads only that model; Groq unloads everything
  CHECK: f=~/.local/bin/ffstt; h() { curl -sf http://127.0.0.1:5092/health | /usr/bin/python3 -c 'import json,sys;print("loaded="+",".join(json.load(sys.stdin)["loaded"]))'; }; $f v3 >/dev/null && h && ../menubar/drive.sh ultra >/dev/null && h && $f groq >/dev/null && h && $f ultra >/dev/null && h
  EXPECT: /loaded=parakeet-v3\s+loaded=parakeet-ultra\s+loaded=\s+loaded=parakeet-ultra/
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/ane; path=f399cd52439b/18 entries; output=loaded= | loaded=parakeet-ultra

- [x] G11: A real FreeFlow dictation runs on the chosen model alone (server log shows one transcription, health shows one model)
  EVIDENCE: manual 2026-10-23; server.log 17:34:20Z 'parakeet-ultra transcribed 2296716 bytes in 0.52s: Now based out of all this thread...' (the user's blog request), the only parakeet-v3 transcriptions after the single-model restart are the G3/G10 test-script requests at 17:00 and 17:01 (same test clip), /health loaded=["parakeet-ultra"]
