#!/bin/bash
# Runs the SummonCore tests with the build cache outside the repo (never .build/ inside Google Drive).
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/summon"
mkdir -p "$CACHE"

extra=()
# With only the Command Line Tools selected, swift-testing needs its framework path spelled out.
if ! xcode-select -p | grep -q "Xcode"; then
  fw="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
  if [[ -d $fw/Testing.framework ]]; then
    extra=(-Xswiftc -F -Xswiftc "$fw" -Xlinker -rpath -Xlinker "$fw")
  fi
fi

# ${extra[@]+...}: macOS bash 3.2 treats an empty array as unbound under set -u.
swift test --scratch-path "$CACHE/build" ${extra[@]+"${extra[@]}"} "$@"
