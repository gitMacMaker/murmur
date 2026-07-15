#!/bin/bash
set -euo pipefail

# Build script for Murmur.
# Compiles all Swift sources, bundles into a .app, ad-hoc codesigns,
# and (by default) launches it. Usage:
#   ./build.sh           # build + launch
#   ./build.sh --no-run  # build only

cd "$(dirname "$0")"

ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
APP_NAME="Murmur"
APP_BUNDLE="/Applications/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"
EXEC_PATH="$MACOS_DIR/$APP_NAME"

RUN=1
for arg in "$@"; do
    case "$arg" in
        --no-run) RUN=0 ;;
    esac
done

echo "→ Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

SOURCES=(
    "MurmurApp.swift"
    "Transcriber.swift"
    "HotkeyManager.swift"
    "PillPanel.swift"
    "TextCleaner.swift"
    "Settings.swift"
    "Onboarding.swift"
    "Theme.swift"
    "Inserter.swift"
    "APIPolish.swift"
)

echo "→ Compiling Swift sources"
xcrun swiftc \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macos14.0 \
    -swift-version 5 \
    -O \
    -framework AppKit -framework SwiftUI -framework AVFoundation \
    -framework Speech -framework ServiceManagement \
    -o "$EXEC_PATH" \
    "${SOURCES[@]}"

echo "→ Installing Info.plist + icon"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp AppIcon.icns "$RES_DIR/AppIcon.icns"

# Sign with a stable identity so TCC permissions (Accessibility, Mic, …)
# survive rebuilds. Ad-hoc signatures change every build, which makes macOS
# treat each build as a new app and re-prompt for everything.
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/{print $2; exit}')
if [[ -n "$SIGN_ID" ]]; then
    echo "→ Codesigning as: $SIGN_ID"
else
    SIGN_ID="-"
    echo "→ Codesigning ad-hoc (no stable identity found — permissions will re-prompt after rebuilds)"
fi
codesign --force --deep --sign "$SIGN_ID" "$APP_BUNDLE"

echo "✔ Built $APP_BUNDLE"

if [[ "$RUN" -eq 1 ]]; then
    echo "→ Relaunching"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.4
    open "$APP_BUNDLE"
fi
