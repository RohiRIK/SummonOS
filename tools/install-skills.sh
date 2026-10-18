#!/usr/bin/env bash
# Links this workspace's skills into Claude Code's user skills folder, so every Claude Code session on
# this Mac can use MacUX, MacAppBuild, etc., not only sessions started inside the workspace.
#   tools/install-skills.sh              link every skill in .claude/skills (idempotent)
#   tools/install-skills.sh --check      list what is linked, missing, or blocked; changes nothing
#   tools/install-skills.sh --uninstall  remove only the links this script made
# Links are symlinks, so `git pull` updates the skills with no reinstall. A real folder with the same
# name in the target is never replaced. Target: $CLAUDE_SKILLS_DIR, else ~/.claude/skills.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
src="$root/.claude/skills"
dest="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mode="${1:-install}"

case "$mode" in
  install | --check | --uninstall) ;;
  *) echo "usage: $0 [--check | --uninstall]" >&2; exit 2 ;;
esac

[ "$mode" = "--check" ] || mkdir -p "$dest"

blocked=0
for skill in "$src"/*/; do
  name=$(basename "$skill")
  target="${skill%/}"
  [ -f "$target/SKILL.md" ] || continue
  link="$dest/$name"

  if [ -L "$link" ]; then
    current=$(readlink "$link")
    if [ "$current" = "$target" ]; then
      case "$mode" in
        --uninstall) rm "$link"; echo "removed  $name" ;;
        *) echo "linked   $name" ;;
      esac
      continue
    fi
    # A link to somewhere else (an older checkout): repoint it on install, leave it otherwise.
    case "$mode" in
      install) ln -sfn "$target" "$link"; echo "relinked $name (was $current)" ;;
      *) echo "other    $name -> $current" ;;
    esac
  elif [ -e "$link" ]; then
    echo "blocked  $name: $link is a real folder; move it away to use the workspace copy" >&2
    blocked=1
  else
    case "$mode" in
      install) ln -s "$target" "$link"; echo "added    $name" ;;
      --check) echo "missing  $name" ;;
      --uninstall) ;;
    esac
  fi
done

# Links into this workspace whose skill was renamed or removed (e.g. PortOmarchyPlugin -> PortLinuxWidget).
for link in "$dest"/*; do
  [ -L "$link" ] && [ ! -e "$link" ] || continue
  case "$(readlink "$link")" in
    "$src"/*)
      case "$mode" in
        --check) echo "stale    $(basename "$link")" ;;
        *) rm "$link"; echo "removed  $(basename "$link") (skill no longer in the workspace)" ;;
      esac ;;
  esac
done

[ "$mode" = "--uninstall" ] || echo "skills folder: $dest (start a new Claude Code session to pick up changes)"
exit "$blocked"
