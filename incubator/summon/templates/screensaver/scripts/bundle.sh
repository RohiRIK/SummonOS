#!/bin/bash
# Release build of the saver's dynamic library, wrapped in build/Starter.saver and ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/screensaver-starter/build"

SAVER="build/Starter.saver"
swift build --scratch-path "$CACHE" -c release --product Starter
BIN="$(swift build --scratch-path "$CACHE" -c release --show-bin-path)"

rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
cp "$BIN/libStarter.dylib" "$SAVER/Contents/MacOS/Starter"
cp Resources/Info.plist "$SAVER/Contents/Info.plist"
codesign --force --sign - "$SAVER"
echo "$SAVER"
