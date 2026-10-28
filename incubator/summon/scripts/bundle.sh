#!/bin/bash
# Release build of the menu app and the CLI, wrapped in build/Summon.app and ad-hoc signed.
# `--debug` builds the debug configuration instead (DEBUG-only aids such as the panel's PanelFixture, spec E4).
# `--universal` builds arm64 + x86_64 (the release workflow, .github/workflows/release.yml).
# The CLI ships inside the app (Contents/MacOS/summon) next to its shared files (Contents/share/summon),
# which is where `summon path` finds them.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
ARCHS=()
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=debug ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    *) echo "usage: $0 [--debug] [--universal]" >&2; exit 2 ;;
  esac
done

CACHE="$HOME/Library/Caches/macplugins/summon"
APP="build/Summon.app"

echo "Building the $CONFIG configuration"
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --scratch-path "$CACHE/build" --product SummonMenu
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --scratch-path "$CACHE/build" --product summon
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --scratch-path "$CACHE/build" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/share/summon"
cp "$BIN/SummonMenu" "$APP/Contents/MacOS/SummonMenu"
cp "$BIN/summon" "$APP/Contents/MacOS/summon"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon from the 1024 master (design/generate.py), and the menu bar template icon.
ICONSET="$CACHE/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size design/brand/app-icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) design/brand/app-icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp design/brand/app-icon-128.png "$APP/Contents/Resources/app-icon.png"
cp design/brand/menubar-icon.png design/brand/menubar-icon@2x.png design/brand/banner.png "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/agents"
cp Resources/agents/*.svg "$APP/Contents/Resources/agents/"

# Shared files: themes (with wallpapers), skills, config templates, project templates, logo.
cp -R themes "$APP/Contents/share/summon/themes"
rsync -a --exclude .build --exclude .swiftpm --exclude build templates/ "$APP/Contents/share/summon/templates/"
cp -R plugin/skills "$APP/Contents/share/summon/skills"
cp -R config "$APP/Contents/share/summon/config"
cp -R design/brand "$APP/Contents/share/summon/assets"

# Siri, Shortcuts and Spotlight find the App Intents in Sources/SummonMenu through Metadata.appintents. Only Xcode
# projects write it, so gather the module's const values here and run Xcode's processor. Without Xcode (Command
# Line Tools only) the app still works, just without the Siri actions.
if PROCESSOR="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
  META="$CACHE/appintents"
  rm -rf "$META" && mkdir -p "$META"
  echo '["AppEntity","AppEnum","AppIntent","AppShortcutsProvider","DynamicOptionsProvider","EntityQuery","EntityStringQuery","TransientEntity"]' >"$META/protocols.json"
  ls "$PWD"/Sources/SummonMenu/*.swift >"$META/sources.txt"
  SDK="$(xcrun --show-sdk-path)"
  xcrun swiftc -frontend -typecheck -parse-as-library -module-name SummonMenu -target arm64-apple-macos15.0 \
    -sdk "$SDK" -I "$BIN" -I "$BIN/Modules" \
    -emit-const-values-path "$META/SummonMenu.swiftconstvalues" -const-gather-protocols-file "$META/protocols.json" \
    $(cat "$META/sources.txt")
  echo "$META/SummonMenu.swiftconstvalues" >"$META/constvalues.txt"
  "$PROCESSOR" --output "$APP/Contents/Resources" --module-name SummonMenu \
    --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")" --sdk-root "$SDK" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" --platform-family macOS \
    --deployment-target 15.0 --target-triple arm64-apple-macos15.0 --binary-file "$APP/Contents/MacOS/SummonMenu" \
    --source-file-list "$META/sources.txt" --swift-const-vals-list "$META/constvalues.txt" --quiet-warnings >/dev/null
  [ -d "$APP/Contents/Resources/Metadata.appintents" ] || echo "No Metadata.appintents: Siri will not see Summon" >&2
else
  echo "No Xcode: Summon builds without its Siri and Shortcuts actions" >&2
fi

codesign --force --sign - "$APP/Contents/MacOS/summon"
codesign --force --sign - "$APP"
echo "$APP"
