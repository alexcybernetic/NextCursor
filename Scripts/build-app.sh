#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/Build/NextCursor.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build --configuration "$CONFIGURATION" --product NextCursor
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/NextCursor" "$CONTENTS/MacOS/NextCursor"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if [[ -f "$ROOT/Resources/NextCursor.icns" ]]; then
    cp "$ROOT/Resources/NextCursor.icns" "$CONTENTS/Resources/NextCursor.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string NextCursor" "$CONTENTS/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile NextCursor" "$CONTENTS/Info.plist"
fi

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "$CODESIGN_IDENTITY" --identifier com.nextcursor.NextCursorPortable "$APP"

echo "Built $APP"
echo "Run it with: open '$APP'"
