#!/usr/bin/env bash
# Build CropCast and assemble + sign build/CropCast.app (Command Line Tools only).
#
# Signing identity, in order of preference:
#   1. $CROPCAST_SIGN_IDENTITY (used as given; failure aborts the build)
#   2. the keychain certificate "CropCast Self-Signed" (by SHA-1)
#   3. ad-hoc (the Screen Recording grant will not survive rebuilds)
# See README.md, "Stable code signing".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/CropCast.app"
CERT_NAME="CropCast Self-Signed"

swift build -c release --product CropCast
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CropCast" "$APP/Contents/MacOS/CropCast"
cp Support/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
# Copied before codesign so the icon is part of the sealed resources.
cp Support/AppIcon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${CROPCAST_SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$CROPCAST_SIGN_IDENTITY"
  echo "Signing with CROPCAST_SIGN_IDENTITY: $IDENTITY"
else
  # Output lines look like: 1) <SHA-1> "CropCast Self-Signed"
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -v name="\"$CERT_NAME\"" '$0 ~ name { print $2; exit }')"
  if [[ -n "$IDENTITY" ]]; then
    echo "Signing with keychain certificate '$CERT_NAME' ($IDENTITY)"
  else
    IDENTITY="-"
    echo "WARNING: no signing identity found; signing ad-hoc." >&2
    echo "         Screen Recording permission will be lost on every rebuild." >&2
    echo "         See README.md, section 'Stable code signing'." >&2
  fi
fi

codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign -dv "$APP"
echo "Built $APP"
