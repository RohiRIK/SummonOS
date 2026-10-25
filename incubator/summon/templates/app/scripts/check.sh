#!/bin/bash
# The gate before calling a change done: build, tests, plist lint, bundle. Writes build/check-report.md.
# Runs the same on your Mac and in CI (added with the private repo by `summon project repo`).
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/app-starter/build"

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

echo "# app-starter check $(date -u +%Y-%m-%dT%H:%MZ)" >"$REPORT"
step build swift build --scratch-path "$CACHE"
step tests scripts/test.sh
step plist plutil -lint Resources/Info.plist
step bundle scripts/bundle.sh
cat "$REPORT"
exit $status
