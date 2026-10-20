#!/bin/bash
# Release build wrapped in build/Starter.app and ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/menubar-starter/build"

APP="build/Starter.app"
swift build --scratch-path "$CACHE" -c release --product Starter
BIN="$(swift build --scratch-path "$CACHE" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Starter" "$APP/Contents/MacOS/Starter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
