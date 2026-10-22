#!/usr/bin/env bash
# Run `swift test` for a SwiftPM package using only the Command Line Tools.
# The CLT ship Swift Testing but SwiftPM does not find it without these paths.
# Usage: scripts/swift-test.sh [package-dir] [extra swift test args...]
set -euo pipefail

PKG_DIR="${1:-.}"
shift || true

DEV_DIR="$(xcode-select -p)"
FW="$DEV_DIR/Library/Developer/Frameworks"
LIB="$DEV_DIR/Library/Developer/usr/lib"

if [[ -d "$FW/Testing.framework" ]]; then
  exec swift test --package-path "$PKG_DIR" \
    -Xswiftc -F"$FW" -Xlinker -F"$FW" \
    -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" "$@"
else
  # Full Xcode install: SwiftPM finds Swift Testing on its own.
  exec swift test --package-path "$PKG_DIR" "$@"
fi
