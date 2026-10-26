#!/bin/bash
# The gate before calling a change done: package build and tests, plist lint, the Xcode build of the app with its
# widget extension, and the bundle checks. Writes build/check-report.md. Needs Xcode (the .appex is an Xcode build).
# Runs the same on your Mac and in CI (added with the private repo by `summon project repo`).
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/widget-starter/build"

mkdir -p build
REPORT="build/check-report.md"
status=0

step() {
  local name=$1
  shift
  if "$@" >"build/$name.log" 2>&1; then
    echo "- [x] $name" >>"$REPORT"
  else
    echo "- [ ] $name (see build/$name.log)" >>"$REPORT"
    status=1
  fi
}

# The app must carry the widget, signed, with the WidgetKit extension point (else it never shows in the gallery).
embedded() {
  local app=$1
  local appex="$app/Contents/PlugIns/StarterWidget.appex"
  [ -d "$appex" ] || { echo "no $appex"; return 1; }
  local point entitlements
  point=$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$appex/Contents/Info.plist")
  [ "$point" = com.apple.widgetkit-extension ] || { echo "extension point is $point"; return 1; }
  codesign --verify --deep --strict "$app"
  # Widget extensions must be sandboxed, or the system never loads them.
  entitlements=$(codesign -d --entitlements - "$appex" 2>&1)
  grep -q com.apple.security.app-sandbox <<<"$entitlements" || { echo "$appex is not sandboxed"; return 1; }
}

echo "# widget-starter check $(date -u +%Y-%m-%dT%H:%MZ)" >"$REPORT"
step build swift build --scratch-path "$CACHE"
step tests scripts/test.sh
step plist plutil -lint Xcode/Config/App-Info.plist Xcode/Config/StarterWidget-Info.plist Xcode/Config/StarterWidget.entitlements
step bundle scripts/bundle.sh
step widget embedded build/Starter.app
cat "$REPORT"
exit $status
