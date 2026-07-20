#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT/dist/Kvist.app}"
SCRATCH="${2:-$ROOT/.build}"
OUTPUT_PARENT="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_PARENT"
STAGE="$(mktemp -d "$OUTPUT_PARENT/.kvist-package.XXXXXX")"
APP_STAGE="$STAGE/Kvist.app"
ICON_SOURCE="$STAGE/Kvist-1024.png"
ICONSET="$STAGE/Kvist.iconset"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$ICONSET" "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"

swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release

BIN_DIR="$(swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release \
  --show-bin-path)"

cp "$BIN_DIR/Kvist" "$APP_STAGE/Contents/MacOS/Kvist"
cp -R "$BIN_DIR/Kvist_Kvist.bundle" "$APP_STAGE/Contents/Resources/"
cp "$ROOT/Resources/Info.plist" "$APP_STAGE/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP_STAGE/Contents/Resources/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES" "$APP_STAGE/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "$ROOT/PRIVACY.md" "$APP_STAGE/Contents/Resources/PRIVACY.md"
/usr/bin/strip -x -T "$APP_STAGE/Contents/MacOS/Kvist"

swift "$ROOT/Tools/make_icon.swift" "$ICON_SOURCE"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_STAGE/Contents/Resources/Kvist.icns"

xattr -cr "$APP_STAGE"
if [[ -n "${KVIST_SIGNING_IDENTITY:-}" ]]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$KVIST_SIGNING_IDENTITY" \
    "$APP_STAGE"
else
  codesign --force --sign - "$APP_STAGE"
  print -u2 "warning: created an ad-hoc-signed local build; do not distribute it"
fi
codesign --verify --deep --strict --verbose=2 "$APP_STAGE"

rm -rf "$OUTPUT"
mv "$APP_STAGE" "$OUTPUT"

echo "$OUTPUT"
