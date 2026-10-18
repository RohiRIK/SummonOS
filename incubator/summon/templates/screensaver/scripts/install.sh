#!/bin/bash
# Installs build/Starter.saver for this user. Pick it in System Settings › Screen Saver afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d build/Starter.saver ]] || scripts/bundle.sh >/dev/null
mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$HOME/Library/Screen Savers/Starter.saver"
cp -R build/Starter.saver "$HOME/Library/Screen Savers/Starter.saver"
# legacyScreenSaver keeps the old copy loaded until it quits.
killall legacyScreenSaver 2>/dev/null || true
echo "Installed. Choose Starter in System Settings › Screen Saver."
