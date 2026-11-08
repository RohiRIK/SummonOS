#!/bin/bash
# Existing app gate, with optional run-specific reports and real Core lifecycle smoke.
set -euo pipefail
cd "$(dirname "$0")/.."

REPORT_DIR=build
RUNTIME_SMOKE=0
SKIP_TESTS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report-dir) [[ $# -ge 2 && -n $2 ]] || { echo "--report-dir needs a directory" >&2; exit 2; }; REPORT_DIR=$2; shift 2 ;;
    --runtime-smoke) RUNTIME_SMOKE=1; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;; # only for CI that already ran the same package tests
    *) echo "usage: $0 [--report-dir DIR] [--runtime-smoke] [--skip-tests]" >&2; exit 2 ;;
  esac
done
mkdir -p "$REPORT_DIR"
MACCTL_CACHE="${SUMMON_CHECK_MACCTL_CACHE:-$HOME/Library/Caches/macplugins/summon/macctl-check}"
REPORT="$REPORT_DIR/check-report.md"
JSON="$REPORT_DIR/check-report.json"
status=0
first_failure=
bundle_ok=0
macctl_ok=0
printf '{"stages":[],"first_failure":null}\n' >"$JSON"
echo "# Summon check $(date -u +%Y-%m-%dT%H:%MZ)" >"$REPORT"

record() {
  python3 - "$JSON" "$1" "$2" "$3" "$4" "$first_failure" <<'PY'
import json,sys
path,name,state,duration,artifact,first=sys.argv[1:]
with open(path) as f: data=json.load(f)
data['stages'].append({'name':name,'status':state,'duration_ms':int(duration),'artifact':artifact})
data['first_failure']=first or None
with open(path,'w') as f: json.dump(data,f,indent=2,sort_keys=True)
PY
}
step() {
  local name=$1; shift
  local began=$(python3 -c 'import time;print(time.monotonic_ns())') state=passed rc=0
  if "$@" >"$REPORT_DIR/$name.log" 2>&1; then
    echo "- [x] $name" >>"$REPORT"
    [[ $name != bundle ]] || bundle_ok=1
    [[ $name != macctl ]] || macctl_ok=1
  else
    rc=$?; state=failed; status=1
    [[ -n $first_failure ]] || first_failure=$name
    echo "- [ ] $name (see $name.log in report directory)" >>"$REPORT"
  fi
  local ended=$(python3 -c 'import time;print(time.monotonic_ns())')
  record "$name" "$state" "$(((ended-began)/1000000))" "$name.log"
  return 0
}
skipped() {
  echo "- [ ] $1 (blocked by $2)" >>"$REPORT"
  record "$1" skipped 0 "$1.log"
}

lint_themes() {
  local ok=0
  for file in themes/*/theme.json; do
    [[ -e $file ]] || continue
    plutil -lint -s "$file" >/dev/null 2>&1 || python3 -m json.tool "$file" >/dev/null || ok=1
  done
  return $ok
}

build_macctl() {
  swift build --package-path ../../macctl -c release \
    --scratch-path "$MACCTL_CACHE" --product macctl
}
verify_identity() {
  local bin
  bin="$(swift build --package-path ../../macctl -c release \
    --scratch-path "$MACCTL_CACHE" --show-bin-path)/macctl"
  python3 ../../tools/build-metadata.py verify \
    --manifest build/Summon.app/Contents/Resources/BuildInfo.json \
    --app build/Summon.app --summon build/Summon.app/Contents/MacOS/summon --macctl "$bin"
}

if [[ $SKIP_TESTS -eq 1 ]]; then skipped tests upstream; else step tests scripts/test.sh; fi
step macctl build_macctl
step bundle scripts/bundle.sh
if [[ $bundle_ok -eq 1 && -f build/Summon.app/Contents/Resources/BuildInfo.json ]]; then
  step siri-actions test -f build/Summon.app/Contents/Resources/Metadata.appintents/extract.actionsdata
  step packaged-signature codesign --verify --deep --strict build/Summon.app
  if [[ $macctl_ok -eq 0 ]]; then
    skipped packaged-identity macctl
  else
    step packaged-identity verify_identity
  fi
  step cli-help build/Summon.app/Contents/MacOS/summon commands --json
else
  for name in siri-actions packaged-signature packaged-identity cli-help; do skipped "$name" bundle; done
fi
step plist plutil -lint Resources/Info.plist
step themes lint_themes
if [[ $RUNTIME_SMOKE -eq 1 ]]; then
  step runtime-core python3 scripts/runtime-audit.py --mode core --iterations 30 --out "$REPORT_DIR/runtime-audit"
fi
cat "$REPORT"
exit "$status"
