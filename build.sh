#!/usr/bin/env bash
# Builds DeskSwipe.app (Apple Silicon) into ./build, signed with the local
# identity from scripts/setup-signing.sh if present, otherwise ad hoc.
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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Prefer the local self-signed identity (scripts/setup-signing.sh): its
# signature stays the same across rebuilds, so macOS keeps the Accessibility
# permission. Without it, sign ad hoc.
SIGNING_IDENTITY_NAME="DeskSwipe Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGNING_IDENTITY_NAME\""; then
    SIGN_WITH="$SIGNING_IDENTITY_NAME"
    echo "==> Signing with \"$SIGN_WITH\""
else
    SIGN_WITH="-"
    echo "==> Signing (ad-hoc; run scripts/setup-signing.sh to keep permissions across rebuilds)"
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
codesign --force --sign "$SIGN_WITH" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo
echo "Built $APP"
echo "Install:  ditto \"$APP\" /Applications/$APP_NAME.app && open /Applications/$APP_NAME.app"
if [[ "$SIGN_WITH" == "-" ]]; then
    echo "Note: each ad-hoc rebuild looks like a new app to macOS, so it may ask for"
    echo "Accessibility permission again (see README > Troubleshooting)."
fi
