#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Kvist.app"
ARCHIVE="$ROOT/dist/Kvist.zip"
NOTARY_PROFILE="${KVIST_NOTARY_PROFILE:-kvist-notary}"

if [[ -n "${KVIST_SIGNING_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$KVIST_SIGNING_IDENTITY"
else
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning \
      | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  print -u2 "error: no Developer ID Application identity is available"
  print -u2 "Create one in Xcode Settings > Accounts > Manage Certificates, then retry."
  exit 1
fi

KVIST_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  "$ROOT/Scripts/package.sh" "$APP"

rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

xcrun notarytool submit \
  "$ARCHIVE" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$ARCHIVE"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

echo "$ARCHIVE"
