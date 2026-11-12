#!/bin/bash
# Builds SoundRoute.app from source and signs it ad-hoc for local use.
# Usage: ./Scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SoundRoute"

APP="dist/SoundRoute.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SoundRoute"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: fine for an app you built yourself on this Mac.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x SoundRoute 2>/dev/null || true
  rm -rf /Applications/SoundRoute.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/SoundRoute.app"
  open /Applications/SoundRoute.app
fi
