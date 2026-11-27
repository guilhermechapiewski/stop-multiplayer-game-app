#!/bin/zsh
# Builds, installs and launches the app on a simulator, then saves a screenshot.
# Usage: tools/run-sim.sh [device-name-or-UDID] [screenshot-path] [extra launch args...]
#   e.g. tools/run-sim.sh "iPhone 17" build/home.png -uiTesting -playerName Gui
# Env:   DERIVED_DATA=<path> to override the DerivedData directory (default: build/DD, shared with tools/test.sh).
# When several simulators share a name, the one on the newest iOS runtime is used.
set -euo pipefail
DEVICE="${1:-iPhone 17}"
SHOT="${2:-}"
shift $(( $# > 2 ? 2 : $# ))
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID=com.gchapiewski.stopapp

if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
  UDID="$DEVICE"
else
  UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | tail -1 | grep -oE '[0-9A-F-]{36}')
  [[ -n "$UDID" ]] || { echo "No simulator named '$DEVICE'" >&2; exit 1; }
fi

DD="${DERIVED_DATA:-$ROOT/build/DD}"
xcodebuild -project "$ROOT/App/Stop.xcodeproj" -scheme Stop \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" build -quiet
xcrun simctl boot "$UDID" 2>/dev/null || true
APP="$DD/Build/Products/Debug-iphonesimulator/Stop.app"
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
if [[ -n "$SHOT" ]]; then
  sleep 3
  xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1
  echo "screenshot: $SHOT"
fi
