#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SPACE"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
DMG_STAGING="$ROOT/build/dmg-staging"
DMG_OUTPUT="$ROOT/dist/$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found. Run ./build.sh first." >&2
  exit 1
fi

rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING" "$(dirname "$DMG_OUTPUT")"

cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -sf /Applications "$DMG_STAGING/Applications"

if [[ -f "$ROOT/SPACE/Assets/AppIcon.icns" ]]; then
  cp "$ROOT/SPACE/Assets/AppIcon.icns" "$DMG_STAGING/.VolumeIcon.icns"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$DMG_STAGING"
  fi
fi

rm -f "$DMG_OUTPUT"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_OUTPUT"

echo "Created $DMG_OUTPUT"
