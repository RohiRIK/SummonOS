#!/usr/bin/env bash
# Local CI: what .github/workflows/swift.yml does, run on this Mac, with the result posted on the commit as a
# GitHub commit status (free; no Actions minutes). The owner does not pay for GitHub Actions, so this is the gate:
# merge a PR only when its head commit has a green "local / swift (macOS)" status.
#
#   tools/local-ci.sh [ref|pr-number] [--no-post]
#
# Builds and tests every Package.swift outside .build/ and plugins/ from a clean checkout of exactly that commit.
set -euo pipefail
set -m  # each background build is its own process group for interruption cleanup

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly CONTEXT="local / swift (macOS)"
ref=HEAD post=1
for arg in "$@"; do
  case "$arg" in
    --no-post) post=0 ;;
    *) ref="$arg" ;;
  esac
done

cd "$ROOT"
if [[ $ref =~ ^[0-9]+$ ]]; then
  ref="$(gh pr view "$ref" --json headRefOid -q .headRefOid)"
  /usr/bin/git fetch -q origin "$ref" 2>/dev/null || /usr/bin/git fetch -q origin
fi
sha="$(/usr/bin/git rev-parse "$ref^{commit}")"
toolchain="$(swift --version | shasum -a 256 | cut -c1-12)"
cache="$HOME/Library/Caches/macplugins/local-ci/$toolchain/release"
parent="$(mktemp -d)"
run_id="${parent##*/}"
tree="$parent/checkout"
logs="$cache/logs/$sha/$run_id"
pending=0
terminal_state=error
terminal_description="Interrupted or failed before completion"
worktree_added=0
active_pid=
scratch_paths=()
status() {
  [[ $post == 1 ]] || return 0
  gh api -X POST "repos/{owner}/{repo}/statuses/$sha" -f state="$1" \
    -f context="$CONTEXT" -f description="$2" >/dev/null
}
cleanup() {
  local result=$? cleanup_failed=0
  trap - EXIT INT TERM
  if [[ -n $active_pid ]] && kill -0 -- "-$active_pid" 2>/dev/null; then
    kill -TERM -- "-$active_pid" 2>/dev/null || cleanup_failed=1
    wait "$active_pid" 2>/dev/null || true
    active_pid=
  fi
  if [[ $worktree_added -eq 1 ]]; then
    if ! /usr/bin/git -C "$ROOT" worktree remove --force "$tree"; then
      echo "local CI: worktree removal failed; inspect $parent" >&2
      cleanup_failed=1
    fi
  fi
  for scratch in ${scratch_paths[@]+"${scratch_paths[@]}"}; do
    if ! rm -rf -- "$scratch"; then
      echo "local CI: scratch cleanup failed: $scratch" >&2
      cleanup_failed=1
    fi
  done
  if [[ $cleanup_failed -eq 0 ]] && ! rmdir "$parent"; then
    echo "local CI: temporary parent removal failed: $parent" >&2
    cleanup_failed=1
  fi
  if [[ $cleanup_failed -eq 1 ]]; then
    terminal_state=error
    terminal_description="Worktree cleanup failed"
    [[ $result -ne 0 ]] || result=1
  elif [[ $result -ne 0 && $terminal_state == success ]]; then
    terminal_state=error
    terminal_description="Local CI interrupted"
  fi
  if [[ $pending -eq 1 ]] && ! status "$terminal_state" "$terminal_description"; then
    echo "local CI: could not post terminal $terminal_state status" >&2
    [[ $result -ne 0 ]] || result=1
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$logs"
/usr/bin/git worktree add -q --detach "$tree" "$sha"
worktree_added=1
status pending "Building and testing on $(hostname -s)"
pending=1
packages=()
while IFS= read -r dir; do packages+=("$dir"); done < <(
  cd "$tree" && find . -name Package.swift -not -path '*/.build/*' -not -path './plugins/*' -exec dirname {} \; |
    sed 's|^\./||' | sort)

failed=()
for package in "${packages[@]}"; do
  slug="${package//\//-}"
  log="$logs/$slug.log"
  printf '%-40s ' "$package"
  scratch="$cache/build/$slug/$sha/$run_id"
  scratch_paths+=("$scratch")
  (cd "$tree/$package" &&
      swift build --build-tests --scratch-path "$scratch" &&
      swift test --skip-build --scratch-path "$scratch") >"$log" 2>&1 &
  active_pid=$!
  if wait "$active_pid"; then
    active_pid=
    echo pass
  else
    active_pid=
    echo "FAIL ($log)"
    failed+=("$package")
  fi
done
if [[ -f $tree/incubator/summon/Package.swift ]]; then
  scratch_paths+=("$cache/build/macctl-check/$sha/$run_id" "$cache/build/summon-bundle/$sha/$run_id")
  (cd "$tree" && SUMMON_CHECK_MACCTL_CACHE="$cache/build/macctl-check/$sha/$run_id" \
      SUMMON_BUNDLE_CACHE="$cache/build/summon-bundle/$sha/$run_id" \
      incubator/summon/scripts/check.sh --skip-tests \
      --report-dir "$logs/summon-gate" --runtime-smoke) >"$logs/summon-gate.log" 2>&1 &
  active_pid=$!
  if ! wait "$active_pid"; then failed+=("summon-gate"); fi
  active_pid=
fi
macos="$(sw_vers -productVersion)"
if (( ${#failed[@]} == 0 )); then
  terminal_state=success
  terminal_description="${#packages[@]}/${#packages[@]} packages and lifecycle gate passed on macOS $macos"
  echo "local CI: all ${#packages[@]} packages and Summon gate pass at ${sha:0:7}"
else
  terminal_state=failure
  terminal_description="Failed: ${failed[*]}"
  echo "local CI: ${#failed[@]} failed at ${sha:0:7}: ${failed[*]}" >&2
  exit 1
fi
