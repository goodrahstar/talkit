# Gates: Parakeet clipboard dictation for iPhone 16 Pro

OWNS: parakeet-ios/**

Scope: one-target iOS app, signed with a free Apple ID, that keeps Parakeet v3 loaded and turns an Action Button press into text on the clipboard, usable from any app.

- [ ] G1: project generates and builds for a real device with no errors
  CHECK: cd app && xcodegen generate >/dev/null && xcodebuild -scheme Parakeet -destination 'generic/platform=iOS' -allowProvisioningUpdates build 2>&1 | tail -1
  EXPECT: BUILD SUCCEEDED
  EVIDENCE: pending

- [ ] G2: app installs and launches on the iPhone signed with the free personal team
  CHECK: xcrun devicectl device process launch --device "$PHONE" app.parakeet.dictate.rk 2>&1
  EXPECT: Launched application
  EVIDENCE: pending

- [ ] G3: on-device transcription of a known clip matches the reference words (bundled test clip, result written to device log)
  EVIDENCE: pending

- [ ] G4: model reload after the app is force-quit is measured and logged (encoder load ms, second launch); target under 1000 ms
  EVIDENCE: pending

- [ ] G5: Mode A works from another app: Notes open, press Action Button, speak, stop, swipe back, paste gives the spoken text
  EVIDENCE: pending

- [ ] G6: Mode B works without leaving the current app: session on, press Action Button twice in Messages, paste gives the text
  EVIDENCE: pending

- [ ] G7: clipboard write from background verified (UIPasteboard direct, or Shortcuts "Copy to Clipboard" fallback), whichever works is recorded
  EVIDENCE: pending

- [ ] G8: Mode B idle timeout turns the mic off (orange dot gone) after the set minutes
  EVIDENCE: pending

- [ ] G9: battery cost measured: % drop over 60 min with Mode B session idle, screen off
  EVIDENCE: pending
