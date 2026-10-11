#!/usr/bin/env bash
# Builds DeskSwipe.app (Apple Silicon, ad-hoc signed) into ./build.
#
#   ./build.sh            run tests, build release, bundle, sign
#   SKIP_TESTS=1 ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DeskSwipe"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
SWIFT_FLAGS=(-c release --arch arm64)

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    # Includes the MTTouch layout tests: Swift has no static_assert, so this
    # is what stops a mis-sized struct from ever being packaged.
    echo "==> Running tests"
    swift test
fi

echo "==> Building $APP_NAME (release, arm64)"
swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Signing (ad-hoc)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo
echo "Built $APP"
echo "Install:  ditto \"$APP\" /Applications/$APP_NAME.app && open /Applications/$APP_NAME.app"
echo "Note: each rebuild changes the ad-hoc signature, so macOS may ask for"
echo "Accessibility permission again (see README > Troubleshooting)."
