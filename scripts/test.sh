#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/build/tests"
mkdir -p "$TEST_DIR"

swiftc -target "$(uname -m)-apple-macos13.0" -framework AppKit \
  "$ROOT_DIR/Sources/MenuBarLyrics/MenuBarLyricsApp.swift" \
  "$ROOT_DIR/Sources/MenuBarLyrics/FloatingLyricsPanel.swift" \
  "$ROOT_DIR/Sources/MenuBarLyrics/PlaybackController.swift" \
  "$ROOT_DIR/Tests/main.swift" \
  -o "$TEST_DIR/MenuBarLyricsTests"

"$TEST_DIR/MenuBarLyricsTests" "$@"
