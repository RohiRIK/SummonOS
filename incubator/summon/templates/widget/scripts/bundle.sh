#!/bin/bash
# Release build of the app with its widget extension (xcodebuild: SwiftPM can't make an .appex), copied to
# build/Starter.app and signed to run locally (ad hoc). Prints the .app path last.
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/widget-starter/xcode"

APP="build/Starter.app"
xcodebuild -project Xcode/Starter.xcodeproj -scheme Starter -configuration Release \
  -derivedDataPath "$CACHE" -destination 'platform=macOS' build >&2

mkdir -p build
rm -rf "$APP"
ditto "$CACHE/Build/Products/Release/Starter.app" "$APP"
echo "$APP"
