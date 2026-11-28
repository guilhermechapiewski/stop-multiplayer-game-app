#!/bin/bash
# Design previews: a screenshot of every screen (StopUITests/DesignGalleryUITests) in one or more variants,
# downscaled to 600 px wide JPEGs for review.
#
# Usage: tools/design_gallery.sh <dest-dir> <variant>...
#   variant: <lang>-<appearance>[-ax]   lang en | pt-BR, appearance light | dark, -ax = the largest
#            accessibility text size.  e.g.  tools/design_gallery.sh build/gallery en-light en-dark pt-BR-light en-light-ax
# Writes <dest-dir>/<variant>/NN-name.jpg (the full-size PNGs stay in build/gallery-raw/<variant>/, git-ignored).
# The simulator is temporary (iPhone 17, iOS 27.0, created for the run and deleted afterwards).
set -euo pipefail

cd "$(dirname "$0")/.."
[ $# -ge 2 ] || { echo "usage: $0 <dest-dir> <variant>..." >&2; exit 2; }
DEST="$1"; shift
RUNTIME_ID="com.apple.CoreSimulator.SimRuntime.iOS-27-0"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
DD="${GALLERY_DERIVED_DATA:-build/DD}"
WORK="$(mktemp -d)"
UDID=""

cleanup() {
  if [ -n "$UDID" ]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "== Building"
xcodebuild build-for-testing -project Stop.xcodeproj -scheme Stop \
  -destination "generic/platform=iOS Simulator" -derivedDataPath "$DD" >"$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log" >&2; echo "error: the build failed." >&2; exit 1; }

UDID=$(xcrun simctl create "Stop design gallery" "$DEVICE_TYPE" "$RUNTIME_ID")
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState discharging --batteryLevel 100 \
  --wifiMode active --wifiBars 3 --cellularMode notSupported

for variant in "$@"; do
  case "$variant" in
    pt-BR-*) lang=pt-BR; rest="${variant#pt-BR-}" ;;
    en-*) lang=en; rest="${variant#en-}" ;;
    *) echo "error: unknown variant $variant" >&2; exit 2 ;;
  esac
  appearance="${rest%%-*}"
  size=large
  [[ "$rest" == *-ax ]] && size=accessibility-extra-extra-extra-large
  echo "== $variant ($lang, $appearance, $size)"
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl ui "$UDID" content_size "$size"
  raw="build/gallery-raw/$variant"
  rm -rf "$raw"; mkdir -p "$raw"
  TEST_RUNNER_GALLERY_DIR="$PWD/$raw" TEST_RUNNER_GALLERY_LANG="$lang" \
    xcodebuild test-without-building -project Stop.xcodeproj -scheme Stop \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" -parallel-testing-enabled NO \
    -only-testing:StopUITests/DesignGalleryUITests >"$WORK/$variant.log" 2>&1 \
    || { grep -E "error|failed" "$WORK/$variant.log" | tail -20 >&2; echo "warning: some shots failed ($variant)" >&2; }
  out="$DEST/$variant"
  rm -rf "$out"; mkdir -p "$out"
  for png in "$raw"/*.png; do
    [ -e "$png" ] || continue
    sips -s format jpeg -s formatOptions 72 --resampleWidth 600 "$png" \
      --out "$out/$(basename "${png%.png}").jpg" >/dev/null
  done
  echo "   $(ls "$out" | wc -l | tr -d ' ') shots in $out"
done
