#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SPACE"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/SPACE Local Code Signing|Developer ID Application|Apple Development|Mac Developer/ { print $2; exit }'
  )"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  echo "warning: no stable code-signing identity found; using ad-hoc signing." >&2
  echo "warning: run scripts/create-local-signing-cert.sh once to preserve Accessibility permission across builds." >&2
else
  echo "Signing with identity: $SIGN_IDENTITY"
fi

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
  -framework CoreFoundation \
  -framework ServiceManagement

cp "$ROOT/SPACE/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ ! -f "$ROOT/SPACE/Assets/AppIcon.icns" ]]; then
  "$ROOT/scripts/build-icon.sh"
fi
cp "$ROOT/SPACE/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

codesign --force --deep --timestamp=none --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
