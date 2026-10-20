#!/usr/bin/env bash
# Publish a plugin's branch to its PUBLIC repo as one clean commit.
# Dev history stays in the private <name>-dev repo; the public repo gets snapshots only.
#
#   tools/publish-public.sh plugins/<name> [branch] "<commit message>"
#
# - Exports the branch (git archive), drops agent memory (PROJECT-CONTEXT.md).
# - Refuses to publish if any pattern in tools/private-patterns.txt matches (email, home subnet,
#   MAC addresses, private hostnames). That file is gitignored: it holds the private values.
# - Commits with the GitHub noreply identity, so no personal email reaches the public history.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN="$(cd "${1:?plugin directory required}" && pwd)"
readonly BRANCH="${2:-main}"
readonly MESSAGE="${3:?commit message required}"
NAME="$(basename "$PLUGIN")"
readonly PATTERNS="$ROOT/tools/private-patterns.txt"
WORK="$(mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT

[[ -f "$PATTERNS" ]] || { echo "Missing $PATTERNS (one regex per line)." >&2; exit 1; }

git -C "$PLUGIN" archive "$BRANCH" | tar -x -C "$WORK"
/bin/rm -f "$WORK/PROJECT-CONTEXT.md"

bash "$ROOT/tools/private-scan.sh" "$PATTERNS" "$WORK"

# Do not contact GitHub until the complete export has passed the privacy gate.
USER_LOGIN="$(gh api user -q .login)"
NOREPLY="$(gh api user -q .id)+${USER_LOGIN}@users.noreply.github.com"

git clone -q "https://github.com/${USER_LOGIN}/${NAME}.git" "$WORK/.public"
rsync -a --delete --exclude .git --exclude .public "$WORK/" "$WORK/.public/"
cd "$WORK/.public"
git add -A
if git diff --cached --quiet; then
  echo "Public repo already matches $BRANCH."
  exit 0
fi
GIT_AUTHOR_NAME="$USER_LOGIN" GIT_AUTHOR_EMAIL="$NOREPLY" \
GIT_COMMITTER_NAME="$USER_LOGIN" GIT_COMMITTER_EMAIL="$NOREPLY" \
  git -c core.hooksPath=/dev/null commit -qm "$MESSAGE"
git -c core.hooksPath=/dev/null push -q origin HEAD
echo "Published $BRANCH to https://github.com/${USER_LOGIN}/${NAME}"
