#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${WALLFLOW_BUILD_DIR:-$PROJECT_DIR/.build}"
APP_DIR="${WALLFLOW_APP_DIR:-$PROJECT_DIR/dist/WallFlow.app}"

swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --product VideoWallpaper
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --show-bin-path)"

# Sign away from synced folders, which can add Finder metadata during signing.
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wallflow-build.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED_APP="$STAGE_DIR/WallFlow.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/VideoWallpaper" "$STAGED_APP/Contents/MacOS/VideoWallpaper"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$(dirname "$APP_DIR")"
ditto --norsrc --noextattr "$STAGED_APP" "$APP_DIR"
printf 'App: %s\n' "$APP_DIR"
