#!/usr/bin/env bash
# Local CI: what .github/workflows/swift.yml does, run on this Mac, with the result posted on the commit as a
# GitHub commit status (free; no Actions minutes). The owner does not pay for GitHub Actions, so this is the gate:
# merge a PR only when its head commit has a green "local / swift (macOS)" status.
#
#   tools/local-ci.sh [ref|pr-number] [--no-post]
#
# Builds and tests every Package.swift outside .build/ and plugins/ from a clean checkout of exactly that commit.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly CONTEXT="local / swift (macOS)"
ref="HEAD"
post=1
for arg in "$@"; do
  case "$arg" in
    --no-post) post=0 ;;
    *) ref="$arg" ;;
  esac
done

cd "$ROOT"
if [[ $ref =~ ^[0-9]+$ ]]; then
  ref="$(gh pr view "$ref" --json headRefOid -q .headRefOid)"
  git fetch -q origin "$ref" 2>/dev/null || git fetch -q origin
fi
sha="$(git rev-parse "$ref^{commit}")"
cache="$HOME/Library/Caches/macplugins/local-ci"
tree="$(mktemp -d)/checkout"
logs="$cache/logs/$sha"
mkdir -p "$logs"
git worktree add -q --detach "$tree" "$sha"
trap 'git -C "$ROOT" worktree remove --force "$tree" >/dev/null 2>&1 || true' EXIT

status() {
  [[ $post == 1 ]] || return 0
  gh api -X POST "repos/{owner}/{repo}/statuses/$sha" -f state="$1" -f context="$CONTEXT" -f description="$2" >/dev/null
}

status pending "Building and testing on $(hostname -s)"
packages=()
while IFS= read -r dir; do packages+=("$dir"); done < <(
  cd "$tree" && find . -name Package.swift -not -path '*/.build/*' -not -path './plugins/*' -exec dirname {} \; |
    sed 's|^\./||' | sort)

failed=()
for package in "${packages[@]}"; do
  slug="${package//\//-}"
  log="$logs/$slug.log"
  printf '%-40s ' "$package"
  if (cd "$tree/$package" &&
      swift build --build-tests --scratch-path "$cache/build/$slug" &&
      swift test --skip-build --scratch-path "$cache/build/$slug") >"$log" 2>&1; then
    echo "pass"
  else
    echo "FAIL ($log)"
    failed+=("$package")
  fi
done

macos="$(sw_vers -productVersion)"
if (( ${#failed[@]} == 0 )); then
  status success "${#packages[@]}/${#packages[@]} packages built and tested on macOS $macos"
  echo "local CI: all ${#packages[@]} packages pass at ${sha:0:7}"
else
  status failure "Failed: ${failed[*]}"
  echo "local CI: ${#failed[@]} failed at ${sha:0:7}: ${failed[*]}" >&2
  exit 1
fi
