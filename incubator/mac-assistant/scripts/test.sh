#!/usr/bin/env bash
# Run the Core test suite. Works on macOS (Xcode or Command Line Tools) and Linux (Swift toolchain).
set -euo pipefail
cd "$(dirname "$0")/.."
APP=mac-assistant

if [[ "$(uname)" == "Darwin" ]]; then
    # Never let SwiftPM write .build/ inside Google Drive.
    SCRATCH="$HOME/Library/Caches/macplugins/$APP"
    EXTRA=()
    # Command Line Tools ship Testing.framework off the default search path.
    if ! xcode-select -p | grep -q Xcode.app; then
        FW="$(xcode-select -p)/Library/Developer/Frameworks"
        EXTRA=(-Xswiftc -F -Xswiftc "$FW" -Xlinker -rpath -Xlinker "$FW")
    fi
    swift test --scratch-path "$SCRATCH" ${EXTRA[@]+"${EXTRA[@]}"} "$@"
else
    # Linux (cloud sessions): toolchain from /opt/swift if it is not on PATH.
    if ! command -v swift >/dev/null && [[ -x /opt/swift/usr/bin/swift ]]; then
        export PATH="/opt/swift/usr/bin:$PATH"
    fi
    swift test "$@"
fi
