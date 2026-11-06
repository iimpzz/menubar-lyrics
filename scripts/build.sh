#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/MenuBarLyrics.app"
DIST_DIR="$ROOT_DIR/dist"

rm -rf "$ROOT_DIR/build" "$DIST_DIR"
mkdir -p "$BUILD_DIR/Contents/MacOS" "$BUILD_DIR/Contents/Resources" "$DIST_DIR"

cp "$ROOT_DIR/Info.plist" "$BUILD_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Sources/NowPlayingProbe/main.swift" "$BUILD_DIR/Contents/Resources/NowPlayingProbe.swift"

swiftc -O -target "$(uname -m)-apple-macos13.0" -framework AppKit \
  "$ROOT_DIR"/Sources/MenuBarLyrics/*.swift \
  -o "$BUILD_DIR/Contents/MacOS/MenuBarLyrics"

codesign --force --deep --sign - "$BUILD_DIR"

cp -R "$BUILD_DIR" "$DIST_DIR/MenuBarLyrics.app"
(cd "$DIST_DIR" && ditto -c -k --keepParent MenuBarLyrics.app MenuBarLyrics.zip)

echo "Built $DIST_DIR/MenuBarLyrics.app"
echo "Built $DIST_DIR/MenuBarLyrics.zip"
