#!/bin/bash
# Makes a project of every template kind (or the kinds named) with the real `summon project new`, in a temporary
# HOME so your config and ~/Summon are never touched, then runs each project's own scripts/check.sh.
# CI runs it once per kind (.github/workflows/templates.yml). Usage: scripts/check-templates.sh [kind...]
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD

kinds=("$@")
[ ${#kinds[@]} -gt 0 ] || kinds=(menubar menubar-panel launcher hud notch app widget cli screensaver)

CACHE="$HOME/Library/Caches/macplugins/summon/build"
swift build --scratch-path "$CACHE" --product summon
summon="$(swift build --scratch-path "$CACHE" --show-bin-path)/summon"

temp=$(mktemp -d)
trap '/bin/rm -rf "$temp"' EXIT
export HOME="$temp/home" SUMMON_PATH="$root"
export GIT_AUTHOR_NAME="Summon CI" GIT_AUTHOR_EMAIL="ci@example.invalid"
export GIT_COMMITTER_NAME="Summon CI" GIT_COMMITTER_EMAIL="ci@example.invalid"
mkdir -p "$HOME"
# The owner's standing approval would create a GitHub repo for every new project: ask instead (never `project repo`).
"$summon" default repos ask
# A summon that ignores $HOME would have written to the real home: stop before it makes projects there too.
[ -f "$HOME/.config/summon/defaults/repos" ] || { echo "summon did not use the temporary HOME" >&2; exit 1; }

status=0
for kind in "${kinds[@]}"; do
  echo "== $kind"
  dir=$("$summon" project new "demo-$kind" --kind "$kind" | head -1)
  if "$dir/scripts/check.sh"; then
    echo "== $kind: check passed"
  else
    status=1
    echo "== $kind: check failed"
    for log in "$dir"/build/*.log; do
      echo "--- $log"
      tail -60 "$log"
    done
  fi
done
exit $status
