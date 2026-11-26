#!/usr/bin/env bash
# Usage: tools/test.sh [package|app|all]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."

run_package() {
  swift test --package-path Packages/StopKit
}

run_app() {
  local sim
  local devices
  devices="$(xcrun simctl list devices available)"
  if grep -q "iPhone 17 (" <<<"$devices"; then
    sim="iPhone 17"
  else
    sim="$(grep -oE 'iPhone[^(]*[^ (]' <<<"$devices" | head -n 1 | sed 's/ *$//')"
  fi
  xcodebuild test -project App/Stop.xcodeproj -scheme Stop \
    -destination "platform=iOS Simulator,name=$sim"
}

case "${1:-all}" in
  package) run_package ;;
  app) run_app ;;
  all)
    run_package
    if [ -d App/Stop.xcodeproj ]; then
      run_app
    else
      echo "Notice: App/Stop.xcodeproj does not exist yet; skipping app tests."
    fi
    ;;
  *) echo "Usage: $0 [package|app|all]" >&2; exit 2 ;;
esac
