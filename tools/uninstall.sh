#!/usr/bin/env bash
# Preview by default. --apply removes only entries matching the private install receipt.
# Projects, themes, configuration, checkpoints and scheduled tasks always remain.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in
  "" | --apply) ;;
  *) echo "Usage: tools/uninstall.sh [--apply]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Usage: tools/uninstall.sh [--apply]" >&2; exit 2; }
exec python3 "$ROOT/incubator/summon/scripts/install-state.py" uninstall "$@"
