#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/SPACE/Assets"
ICONSET="$ASSETS/AppIcon.iconset"
ICNS="$ASSETS/AppIcon.icns"
SOURCE_VECTOR="$ASSETS/icon-source.svg"
SOURCE_BASE="$ASSETS/icon-base.png"
SOURCE="$ASSETS/icon-square.png"

if [[ -f "$SOURCE_VECTOR" ]]; then
  if sips -s format png "$SOURCE_VECTOR" --out "$SOURCE_BASE" >/dev/null 2>&1; then
    sips -z 1024 1024 "$SOURCE_BASE" --out "$SOURCE" >/dev/null
  elif [[ ! -f "$SOURCE" ]]; then
    echo "Could not convert $SOURCE_VECTOR and $SOURCE is missing." >&2
    exit 1
  fi
elif [[ ! -f "$SOURCE" ]]; then
  echo "Missing $SOURCE_VECTOR and $SOURCE" >&2
  exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

make_icon() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
}

make_icon 16  icon_16x16.png
make_icon 32  icon_16x16@2x.png
make_icon 32  icon_32x32.png
make_icon 64  icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Created $ICNS"
