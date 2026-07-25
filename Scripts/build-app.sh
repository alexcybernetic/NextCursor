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
cp "$ROOT/Resources/NextCursor.icns" "$CONTENTS/Resources/NextCursor.icns"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "$CODESIGN_IDENTITY" --identifier com.nextcursor.NextCursorPortable "$APP"

echo "Built $APP"
echo "Run it with: open '$APP'"
