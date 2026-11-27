#!/usr/bin/env bash
# Usage: tools/test.sh [package|app|all]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."

run_package() {
  swift test --package-path Packages/StopKit
}

run_app() {
  local sim devices dd="build/DD"
  devices="$(xcrun simctl list devices available)"
  if grep -qE '^ +iPhone 17 \(' <<<"$devices"; then
    sim="iPhone 17"
  else
    # Device lines look like "    iPhone 16 Pro (UDID) (Shutdown)"; runtime headers ("-- iOS 27.0 --") are skipped.
    sim="$(grep -E '^ +iPhone' <<<"$devices" | head -n 1 | sed -E 's/^ +//; s/ \(.*$//')"
  fi
  if [ -z "$sim" ]; then
    echo "error: no available iPhone simulator" >&2
    exit 1
  fi
  xcodebuild test -project Stop.xcodeproj -scheme Stop \
    -destination "platform=iOS Simulator,name=$sim" \
    -derivedDataPath "$dd" -parallel-testing-enabled NO
  local manifest="$dd/Build/Products/Debug-iphonesimulator/Stop.app/PrivacyInfo.xcprivacy"
  if [ ! -f "$manifest" ]; then
    echo "error: PrivacyInfo.xcprivacy is missing from the app bundle ($manifest)" >&2
    exit 1
  fi
  echo "Privacy manifest present in app bundle."
}

case "${1:-all}" in
  package) run_package ;;
  app) run_app ;;
  all)
    run_package
    if [ -d Stop.xcodeproj ]; then
      run_app
    else
      echo "Notice: Stop.xcodeproj does not exist yet; skipping app tests."
    fi
    ;;
  *) echo "Usage: $0 [package|app|all]" >&2; exit 2 ;;
esac
