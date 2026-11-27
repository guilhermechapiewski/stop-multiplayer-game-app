#!/bin/bash
# App Store and website screenshots.
#
# Runs StopUITests/ScreenshotTests (a seeded mock game: fixed letter, fixed bot answers, no personal data) on
# an iPhone 17 Pro Max (6.9", 1320x2868) and an iPhone 17 (6.3", 1206x2622), in English and Portuguese, with
# light appearance and a 9:41 status bar. The raw shots land in build/screenshots-raw/<device>/<locale>/
# (git-ignored); tools/frame_screenshots.swift then captions them into
#   appstore/screenshots/{iphone,iphone-medium}/{en-US,pt-BR}/NN-name.png   (exact App Store sizes)
#   docs/images/screens/{en-US,pt-BR}/NN-name.jpg                           (600 px wide, for the website)
#
# The simulators are temporary (created for the run, deleted afterwards), so this never disturbs the ones
# tools/test.sh or Xcode use. Needs Xcode with the iOS 27.0 simulator runtime.
# Usage: tools/screenshots.sh [--frame-only]   (--frame-only re-frames the existing raw shots)
set -euo pipefail

cd "$(dirname "$0")/.."
RUNTIME_ID="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
# "folder|device type id"
DEVICES=(
  "iphone|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
  "iphone-medium|com.apple.CoreSimulator.SimDeviceType.iPhone-17"
)
LOCALES=(en-US pt-BR)
RAW="build/screenshots-raw"
# Shares tools/test.sh's derived data (incremental builds); set SCREENSHOTS_DERIVED_DATA to keep them apart.
DD="${SCREENSHOTS_DERIVED_DATA:-build/DD}"
WORK="$(mktemp -d)"
CREATED=()

cleanup() {
  for udid in "${CREATED[@]+"${CREATED[@]}"}"; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

fail() { echo "error: $*" >&2; exit 1; }

frame() {
  echo "== Framing"
  swift tools/frame_screenshots.swift "$RAW" appstore/screenshots docs/images/screens
}

if [ "${1:-}" = "--frame-only" ]; then
  frame
  exit 0
fi

xcrun simctl list runtimes | grep -q "$RUNTIME_ID" \
  || fail "the iOS 27.0 simulator runtime is not installed (install it in Xcode > Settings > Components)."

echo "== Building"
xcodebuild build-for-testing -project App/Stop.xcodeproj -scheme Stop \
  -destination "generic/platform=iOS Simulator" -derivedDataPath "$DD" >"$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log" >&2; fail "the build failed."; }

for entry in "${DEVICES[@]}"; do
  key="${entry%%|*}"; type="${entry##*|}"
  xcrun simctl list devicetypes | grep -q "$type" || fail "device type $type is not available in this Xcode."
  echo "== $key"
  udid=$(xcrun simctl create "Stop screenshots ($key)" "$type" "$RUNTIME_ID") \
    || fail "could not create a $type simulator."
  CREATED+=("$udid")
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance light
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState discharging --batteryLevel 100 \
    --wifiMode active --wifiBars 3 --cellularMode notSupported

  for locale in "${LOCALES[@]}"; do
    echo "   $locale"
    bundle="$WORK/$key-$locale.xcresult"
    # TEST_RUNNER_-prefixed variables reach the tests without the prefix; ScreenshotTests skip without it.
    TEST_RUNNER_STOP_SCREENSHOTS=1 TEST_RUNNER_STOP_SCREENSHOTS_LANG="$locale" \
      xcodebuild test-without-building -project App/Stop.xcodeproj -scheme Stop \
      -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DD" -parallel-testing-enabled NO \
      -only-testing:StopUITests/ScreenshotTests -resultBundlePath "$bundle" >"$WORK/$key-$locale.log" 2>&1 \
      || { grep -E "error|failed" "$WORK/$key-$locale.log" | tail -20 >&2; fail "ScreenshotTests failed ($key, $locale)."; }

    export_dir="$WORK/$key-$locale-raw"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$export_dir" >/dev/null
    dest="$RAW/$key/$locale"
    rm -rf "$dest"; mkdir -p "$dest"
    # Name each file after its attachment ("01-lobby" ...), from the export manifest.
    python3 -I - "$export_dir" "$dest" <<'PY'
import json, os, re, shutil, sys
raw, dest = sys.argv[1:3]
count = 0
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for a in test["attachments"]:
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", os.path.splitext(a["suggestedHumanReadableName"])[0])
        if re.fullmatch(r"\d\d-[a-z-]+", name):
            shutil.copy(os.path.join(raw, a["exportedFileName"]), os.path.join(dest, name + ".png"))
            count += 1
if count != 7:
    sys.exit(f"expected 7 screenshots, got {count}")
PY
  done
  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
done

frame
echo "== Done"
find appstore/screenshots docs/images/screens -type f \( -name '*.png' -o -name '*.jpg' \) | sort
