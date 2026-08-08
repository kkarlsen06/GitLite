#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Kvist.app}"
DMG="${2:-$ROOT/dist/Kvist.dmg}"
VOLNAME="Kvist"
MOUNT="/Volumes/$VOLNAME"

if [[ ! -d "$APP" ]]; then
  print -u2 "error: $APP does not exist; run Scripts/package.sh first"
  exit 1
fi
if [[ -e "$MOUNT" ]]; then
  print -u2 "error: $MOUNT is already mounted; eject it and retry"
  exit 1
fi

STAGE="$(mktemp -d)"
STAGE_ROOT="$STAGE/root"
RW_DMG="$STAGE/Kvist-rw.dmg"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE_ROOT/.background"
cp -R "$APP" "$STAGE_ROOT/Kvist.app"
ln -s /Applications "$STAGE_ROOT/Applications"
swift "$ROOT/Tools/make_dmg_background.swift" "$STAGE_ROOT/.background/background.png"

SIZE_MB=$(( $(du -sm "$STAGE_ROOT" | cut -f1) + 20 ))
hdiutil create \
  -srcfolder "$STAGE_ROOT" \
  -volname "$VOLNAME" \
  -fs HFS+ \
  -format UDRW \
  -size "${SIZE_MB}m" \
  -ov "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen >/dev/null

# Finder writes the icon-view layout into the volume's .DS_Store; this needs
# a logged-in GUI session and Automation permission for Finder.
osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 740, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Kvist.app" of container window to {140, 180}
    set position of item "Applications" of container window to {400, 180}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
for attempt in 1 2 3 4 5; do
  if hdiutil detach "$MOUNT" >/dev/null 2>&1; then
    break
  fi
  if (( attempt == 5 )); then
    print -u2 "error: could not detach $MOUNT"
    exit 1
  fi
  sleep 1
done

rm -f "$DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

if [[ -n "${KVIST_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$KVIST_SIGNING_IDENTITY" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
else
  print -u2 "warning: created an unsigned DMG; do not distribute it"
fi

echo "$DMG"
