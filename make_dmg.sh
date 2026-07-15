#!/bin/bash
set -euo pipefail

# Packages the installed /Applications/Murmur.app into a shareable DMG.
# Run ./build.sh first. Output: dist/Murmur-<version>.dmg

cd "$(dirname "$0")"

APP="/Applications/Murmur.app"
[[ -d "$APP" ]] || { echo "✘ $APP not found — run ./build.sh first" >&2; exit 1; }

VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)
STAGE="dist/stage"
DMG="dist/Murmur-$VERSION.dmg"

rm -rf dist
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Murmur" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✔ $DMG"
