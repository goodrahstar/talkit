#!/bin/bash
# Build Talkit and install it on the iPhone plugged into this Mac.
# Run it every 7 days (free Apple account) or after any change.
set -euo pipefail
cd "$(dirname "$0")/app"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate >/dev/null

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available|connected/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) {print $i; exit}}')
[ -n "$DEVICE" ] || { echo "No iPhone found. Plug it in, unlock it and tap Trust."; exit 1; }
UDID=$(xcrun xctrace list devices 2>/dev/null | awk -F'[()]' '/iPhone/ && !/Simulator/ {print $(NF-1); exit}')

xcodebuild -scheme Parakeet -destination "id=$UDID" -derivedDataPath ../build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build | tail -1
xcrun devicectl device install app --device "$DEVICE" ../build/Build/Products/Debug-iphoneos/Parakeet.app | grep -E "installationURL|rror"
echo "Talkit installed. It stays valid for 7 days with a free Apple account."
