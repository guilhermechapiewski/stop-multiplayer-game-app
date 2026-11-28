#!/usr/bin/env bash
# Runs the test suites.
# Usage: tools/test.sh [unit|ui|all] [extra xcodebuild args, e.g. -only-testing:StopUITests/PracticeUITests]
#   unit  StopKit package tests on macOS, plus the app's unit tests (StopTests) on a simulator.
#   ui    The app's UI tests (StopUITests) on a simulator.
#   all   both (default).
# Env: DEVICE=<simulator name> (default "iPhone 17", else the first available iPhone).
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-all}"
(( $# )) && shift
DD="build/DD"

simulator() {
  local devices
  devices="$(xcrun simctl list devices available)"
  if [ -n "${DEVICE:-}" ]; then
    echo "$DEVICE"
  elif grep -qE '^ +iPhone 17 \(' <<<"$devices"; then
    echo "iPhone 17"
  else
    # Device lines look like "    iPhone 16 Pro (UDID) (Shutdown)"; runtime headers ("-- iOS 27.0 --") are skipped.
    grep -E '^ +iPhone' <<<"$devices" | head -n 1 | sed -E 's/^ +//; s/ \(.*$//'
  fi
}

app_tests() {
  local only="$1"; shift
  local sim
  sim="$(simulator)"
  if [ -z "$sim" ]; then
    echo "error: no available iPhone simulator" >&2
    exit 1
  fi
  # A narrower -only-testing in the extra args replaces the default bundle (xcodebuild would run the union).
  local scope=(-only-testing:"$only")
  for arg in "$@"; do
    [[ "$arg" == -only-testing:"$only"* ]] && scope=()
  done
  echo "▸ $only on $sim"
  xcodebuild test -project Stop.xcodeproj -scheme Stop \
    -destination "platform=iOS Simulator,name=$sim" \
    -derivedDataPath "$DD" -parallel-testing-enabled NO \
    ${scope[@]+"${scope[@]}"} "$@"
}

run_unit() {
  echo "▸ StopKit package tests"
  swift test --package-path Packages/StopKit
  app_tests StopTests "$@"
  local manifest="$DD/Build/Products/Debug-iphonesimulator/Stop.app/PrivacyInfo.xcprivacy"
  if [ ! -f "$manifest" ]; then
    echo "error: PrivacyInfo.xcprivacy is missing from the app bundle ($manifest)" >&2
    exit 1
  fi
  echo "Privacy manifest present in app bundle."
}

run_ui() {
  app_tests StopUITests "$@"
}

case "$MODE" in
  unit) run_unit "$@" ;;
  ui)   run_ui "$@" ;;
  all)  run_unit "$@" && run_ui "$@" ;;
  *)    echo "usage: $0 [unit|ui|all] [xcodebuild args]" >&2; exit 2 ;;
esac
