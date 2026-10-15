#!/usr/bin/env bash
# Packages build/DeskSwipe.app into build/DeskSwipe-<version>.dmg with an
# Applications shortcut for drag-to-install. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DeskSwipe.app"
[[ -d "$APP" ]] || { echo "error: $APP not found; run ./build.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/DeskSwipe-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/DeskSwipe.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "DeskSwipe $VERSION" -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

echo "Built $DMG"
shasum -a 256 "$DMG"
