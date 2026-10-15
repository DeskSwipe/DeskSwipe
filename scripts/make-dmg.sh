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
# APFS image from the staging folder; UDZO (zlib) opens on any supported macOS.
diskutil image create from --format UDZO --volumeName "DeskSwipe $VERSION" \
    "$STAGING" "$DMG" >/dev/null

# Check the result: mount read-only, confirm the app is there and its
# signature is intact, then eject.
MOUNT="$(mktemp -d)"
diskutil image attach --readOnly --nobrowse --mountPoint "$MOUNT" "$DMG" >/dev/null
trap 'diskutil eject "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true; rm -rf "$STAGING"' EXIT
[[ -L "$MOUNT/Applications" ]] || { echo "error: Applications shortcut missing from DMG" >&2; exit 1; }
codesign --verify --strict "$MOUNT/DeskSwipe.app"
diskutil eject "$MOUNT" >/dev/null
rmdir "$MOUNT"
trap 'rm -rf "$STAGING"' EXIT

echo "Built $DMG"
shasum -a 256 "$DMG"
