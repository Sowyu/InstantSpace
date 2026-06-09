#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SPACE"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

swiftc \
  -O \
  -whole-module-optimization \
  -target arm64-apple-macosx13.0 \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  "$ROOT/SPACE/main.swift" \
  "$ROOT/SPACE/AppDelegate.swift" \
  "$ROOT/SPACE/SpaceEngine.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreFoundation

cp "$ROOT/SPACE/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

"$ROOT/scripts/build-icon.sh"
cp "$ROOT/SPACE/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Built $APP_BUNDLE"
