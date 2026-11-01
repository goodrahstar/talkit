# Gates: Parakeet Switch menu bar app

OWNS: ~/parakeet-server/menubar/**, ~/Applications/Parakeet Switch.app/**, ~/Library/LaunchAgents/com.rahul.parakeet-switch.plist

Scope: A menu bar icon shows whether the Parakeet server is on and lets the user turn it on/off and pick Parakeet or Groq with one click, and it starts at login.

- [x] G1: App builds from source into a signed menu-bar-only bundle
  CHECK: ./build.sh && /usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$HOME/Applications/Parakeet Switch.app/Contents/Info.plist" && codesign --verify "$HOME/Applications/Parakeet Switch.app" && echo BUILD_OK
  EXPECT: /true\s+BUILD_OK/
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/menubar; path=b630017d8879/17 entries; output=BUILD_OK | /Users/rahulkumar/Applications/Parakeet Switch.app: replacing existing signature

- [x] G2: App is running and launchd starts it at login
  CHECK: pgrep -f 'Parakeet Switch.app/Contents/MacOS/ParakeetSwitch' >/dev/null && launchctl print gui/$(id -u)/com.rahul.parakeet-switch | grep -q 'path = .*com.rahul.parakeet-switch.plist' && echo RUNNING_AT_LOGIN
  EXPECT: RUNNING_AT_LOGIN
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/menubar; path=b630017d8879/17 entries; output=RUNNING_AT_LOGIN

- [x] G3: App's "turn off" action stops the server and moves FreeFlow to Groq
  CHECK: ./drive.sh off && sleep 3 && ~/.local/bin/ffstt status
  EXPECT: FreeFlow STT: groq | Parakeet server: stopped
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/menubar; path=b630017d8879/17 entries; output=off exit=0 1792699408.7368588 | FreeFlow STT: groq | Parakeet server: stopped

- [x] G4: App's "Parakeet" action turns the server back on and points FreeFlow at it
  CHECK: ./drive.sh parakeet && sleep 3 && ~/.local/bin/ffstt status
  EXPECT: FreeFlow STT: parakeet | Parakeet server: running
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/menubar; path=b630017d8879/17 entries; output=parakeet exit=0 1792699414.861299 | FreeFlow STT: parakeet | Parakeet server: running

- [x] G5: App's "Groq" action switches to Groq and leaves the server on
  CHECK: ./drive.sh groq && sleep 3 && ~/.local/bin/ffstt status
  EXPECT: FreeFlow STT: groq | Parakeet server: running
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/rahulkumar/parakeet-server/menubar; path=b630017d8879/17 entries; output=groq exit=0 1792699419.2691789 | FreeFlow STT: groq | Parakeet server: running

- [ ] G6: User sees the icon, its menu shows the right state, and clicking it toggles the server
  EVIDENCE: pending
