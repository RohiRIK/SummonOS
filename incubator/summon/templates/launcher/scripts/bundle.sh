#!/bin/bash
# Release build wrapped in build/Starter.app and ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/launcher-starter/build"

APP="build/Starter.app"
swift build --scratch-path "$CACHE" -c release --product Starter
BIN="$(swift build --scratch-path "$CACHE" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Starter" "$APP/Contents/MacOS/Starter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
strip -x "$APP/Contents/MacOS/Starter" # release build: drop local symbols for a smaller binary that loads faster
codesign --force --sign - "$APP"
echo "$APP"
