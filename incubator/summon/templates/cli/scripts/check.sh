#!/bin/bash
# The gate before calling a change done: build, tests, a release build that answers --help. Writes build/check-report.md.
# Runs the same on your Mac and in CI (added with the private repo by `summon project repo`).
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/cli-starter/build"

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

echo "# cli-starter check $(date -u +%Y-%m-%dT%H:%MZ)" >"$REPORT"
step build swift build --scratch-path "$CACHE"
step tests scripts/test.sh
step release swift build --scratch-path "$CACHE" -c release
step help swift run --scratch-path "$CACHE" -c release --skip-build cli-starter --help
cat "$REPORT"
exit $status
