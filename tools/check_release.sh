#!/usr/bin/env bash
# Builds the Release configuration for the simulator and checks that Debug-only features stay out of it:
# Practice with bots (owner decision, 2026-11-27) must leave no trace in the Release binary.
# Usage: tools/check_release.sh   Env: DEVICE=<simulator name> (default "iPhone 17").
set -euo pipefail
cd "$(dirname "$0")/.."
DD="build/DDRelease"
xcodebuild build -project Stop.xcodeproj -scheme Stop -configuration Release \
  -destination "platform=iOS Simulator,name=${DEVICE:-iPhone 17}" -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO -quiet
BINARY="$DD/Build/Products/Release-iphonesimulator/Stop.app/Stop"
status=0
for symbol in practiceButton startPracticeButton PracticeSetupView PracticeSetupModel; do
  if strings -a "$BINARY" | grep -q "$symbol"; then
    echo "error: '$symbol' is in the Release binary (Practice with bots is Debug-only)" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "Release build has no Practice with bots."
exit "$status"
