#!/bin/bash
# swift test that also works with only the Command Line Tools (no Xcode): they ship Testing.framework, but not on
# the default search paths, so `swift test` alone fails with "plugin for module 'TestingMacros' not found".
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE="$HOME/Library/Caches/macplugins/screensaver-starter/build"

CLT="/Library/Developer/CommandLineTools/Library/Developer"
# Loading the testing macros in process: through the plugin server they are "not found" about one build in three.
MACROS="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* ]]; then
  exec swift test --scratch-path "$CACHE" \
    -Xswiftc -F -Xswiftc "$CLT/Frameworks" \
    -Xswiftc -load-plugin-library -Xswiftc "$MACROS" \
    -Xlinker -F -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
fi
exec swift test --scratch-path "$CACHE" "$@"
