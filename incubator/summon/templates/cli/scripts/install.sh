#!/bin/bash
# Release build of cli-starter into ~/.local/bin (on PATH for most shells).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product cli-starter
BIN="$(swift build -c release --show-bin-path)"
mkdir -p "$HOME/.local/bin"
cp "$BIN/cli-starter" "$HOME/.local/bin/cli-starter"
echo "$HOME/.local/bin/cli-starter"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Add ~/.local/bin to your PATH to run cli-starter from any terminal." ;;
esac
