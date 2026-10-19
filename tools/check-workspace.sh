#!/usr/bin/env bash
# Workspace hygiene gate. Run from anywhere; CI runs it on every push (snippet: tools/ci/check-workspace.yml).
#   1. No Package.swift outside the allowed roots (plugins live in their own repos).
#   2. No tracked file over 2 MB, except the explicit allowlist below.
#   3. plugins.md is current with plugins.json (tools/mp index --check), when jq is installed.
#   4. docs/ is a conformant OKF bundle with current index.md files (tools/okf-index.py --check).
# Exit 0 when clean, 1 when any check fails.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root"

# Folders that may hold a Swift package. macctl/ and incubator/ leave when they move to their own repos.
ALLOWED_PACKAGE_ROOTS="macctl/ incubator/ examples/"

MAX_BYTES=$((2 * 1024 * 1024))

# Tracked files allowed over MAX_BYTES (shell globs): only the existing Summon wallpapers and brand art.
# They move to Release assets when Summon gets its own repo. Do not widen this without the owner's OK.
LARGE_FILE_ALLOWLIST="incubator/summon/themes/*/*.jpg incubator/summon/themes/*/*.png incubator/summon/design/brand/* incubator/summon/design/wallpapers-preview.png"

fail=0

# 1. Package.swift placement: tracked plus untracked-but-not-ignored, so a new package fails before commit.
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  ok=0
  for allowed in $ALLOWED_PACKAGE_ROOTS; do
    case "$pkg" in "$allowed"*) ok=1 ;; esac
  done
  if [ "$ok" -eq 0 ]; then
    echo "error: Package.swift outside the allowed roots ($ALLOWED_PACKAGE_ROOTS): $pkg" >&2
    fail=1
  fi
done < <(git ls-files --cached --others --exclude-standard | grep -E '(^|/)Package\.swift$' || true)

# 2. File size.
allowed_large=""
while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue # deleted in the work tree
  size=$(wc -c <"$file" | tr -d ' ')
  [ "$size" -gt "$MAX_BYTES" ] || continue
  listed=0
  for pattern in $LARGE_FILE_ALLOWLIST; do
    # shellcheck disable=SC2254 # the pattern is a glob on purpose
    case "$file" in $pattern) listed=1 ;; esac
  done
  if [ "$listed" -eq 1 ]; then
    allowed_large="$allowed_large  $size  $file"$'\n'
  else
    echo "error: tracked file over 2 MB ($size bytes): $file" >&2
    fail=1
  fi
done < <(git ls-files -z)

if [ -n "$allowed_large" ]; then
  echo "Allowlisted files over 2 MB (bytes, path):"
  printf '%s' "$allowed_large"
else
  echo "Allowlisted files over 2 MB: none (allowlist: $LARGE_FILE_ALLOWLIST)"
fi

# 3. Registry index.
if command -v jq >/dev/null 2>&1; then
  MACPLUGINS_HOME="$root" "$root/tools/mp" index --check || fail=1
else
  echo "note: jq is not installed; skipped the plugins.md check"
fi

# 4. Docs bundle.
if command -v python3 >/dev/null 2>&1; then
  python3 "$root/tools/okf-index.py" --check || fail=1
else
  echo "note: python3 is not installed; skipped the docs bundle check"
fi

if [ "$fail" -ne 0 ]; then
  echo "check-workspace: FAILED" >&2
  exit 1
fi
echo "check-workspace: ok"
