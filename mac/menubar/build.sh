#!/bin/bash
# Builds ~/Applications/Parakeet Switch.app from ParakeetSwitch.swift.
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/Parakeet Switch.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -framework AppKit -o "$APP/Contents/MacOS/ParakeetSwitch" ParakeetSwitch.swift
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.rahul.parakeet-switch</string>
  <key>CFBundleName</key><string>Parakeet Switch</string>
  <key>CFBundleExecutable</key><string>ParakeetSwitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.rahul.parakeet-switch</string>
      <key>CFBundleURLSchemes</key><array><string>parakeetswitch</string></array>
    </dict>
  </array>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "built $APP"
