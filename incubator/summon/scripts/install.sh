#!/bin/bash
# Installs Summon for this user: the app in ~/Applications, `summon` on PATH, and the themes in ~/.config/summon.
# Run scripts/bundle.sh first. Safe to run again: it replaces the app and adds themes without touching yours.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Summon.app"
[[ -d $APP ]] || { echo "Run scripts/bundle.sh first." >&2; exit 1; }

mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$HOME/.config/summon/themes"
rm -rf "$HOME/Applications/Summon.app"
cp -R "$APP" "$HOME/Applications/Summon.app"
ln -sf "$HOME/Applications/Summon.app/Contents/MacOS/summon" "$HOME/.local/bin/summon"

# Themes the user has not got yet; an existing theme folder is left alone.
for dir in themes/*/; do
  slug=$(basename "$dir")
  [[ -d "$HOME/.config/summon/themes/$slug" ]] || cp -R "$dir" "$HOME/.config/summon/themes/$slug"
done

"$HOME/.local/bin/summon" menu init >/dev/null
# Summon's skills into every agent's skill folder (Claude Code, Codex, OpenCode, Antigravity).
"$HOME/.local/bin/summon" skills link
echo "Installed. Open ~/Applications/Summon.app, then choose an agent: summon default agent claude"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Add ~/.local/bin to your PATH to use \`summon\` in a terminal." ;;
esac
