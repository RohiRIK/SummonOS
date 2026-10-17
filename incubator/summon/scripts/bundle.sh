#!/bin/bash
# Release build of the menu app and the CLI, wrapped in build/Summon.app and ad-hoc signed.
# The CLI ships inside the app (Contents/MacOS/summon) next to its shared files (Contents/share/summon),
# which is where `summon path` finds them.
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/summon"
APP="build/Summon.app"

swift build -c release --scratch-path "$CACHE/build" --product SummonMenu
swift build -c release --scratch-path "$CACHE/build" --product summon
BIN="$(swift build -c release --scratch-path "$CACHE/build" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/share/summon"
cp "$BIN/SummonMenu" "$APP/Contents/MacOS/SummonMenu"
cp "$BIN/summon" "$APP/Contents/MacOS/summon"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Shared files: themes (with wallpapers), skills, config templates, logo.
for dir in themes skills config assets; do
  [[ -d $dir ]] && cp -R "$dir" "$APP/Contents/share/summon/$dir"
done

codesign --force --sign - "$APP/Contents/MacOS/summon"
codesign --force --sign - "$APP"
echo "$APP"
