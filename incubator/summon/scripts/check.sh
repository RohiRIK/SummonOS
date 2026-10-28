#!/bin/bash
# The gate before a PR: tests, bundle, plist lint, theme JSON lint. Writes build/check-report.md.
set -euo pipefail
cd "$(dirname "$0")/.."

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

lint_themes() {
  local ok=0
  for file in themes/*/theme.json; do
    [[ -e $file ]] || continue
    plutil -lint -s "$file" >/dev/null 2>&1 || python3 -m json.tool "$file" >/dev/null || ok=1
  done
  return $ok
}

echo "# Summon check $(date -u +%Y-%m-%dT%H:%MZ)" >"$REPORT"
step tests scripts/test.sh
step bundle scripts/bundle.sh
step siri-actions test -f build/Summon.app/Contents/Resources/Metadata.appintents/extract.actionsdata
step plist plutil -lint Resources/Info.plist
step themes lint_themes
step cli-help build/Summon.app/Contents/MacOS/summon commands --json

cat "$REPORT"
exit $status
