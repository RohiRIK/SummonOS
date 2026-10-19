#!/bin/bash
# SummonOS installer: Summon (app + `summon` CLI + themes + skills) and macctl, built from source on this Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/RohiRIK/macos-plugins/main/install.sh | bash
#   ./install.sh                     # from a checkout: installs that checkout
#
# Environment:
#   SUMMONOS_HOME   where the checkout lives when piped from curl (default ~/.summonos)
#   SUMMONOS_REF    branch or tag to install (default main)
#
# Safe to run again: it updates the checkout, rebuilds, and keeps your themes, projects and settings.
# Needs macOS 15+, git, and Xcode or the Command Line Tools with Swift 6.
set -euo pipefail

REPO="https://github.com/RohiRIK/macos-plugins.git"
REF="${SUMMONOS_REF:-main}"
BIN="$HOME/.local/bin"
CACHE="$HOME/Library/Caches/macplugins"

say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# 1. This Mac can build it.
[[ $(uname -s) == Darwin ]] || die "SummonOS runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 15 )) || die "SummonOS needs macOS 15 or newer (this Mac has $(sw_vers -productVersion))."
command -v git >/dev/null || die "git is missing. Install the Command Line Tools: xcode-select --install"
command -v swift >/dev/null || die "Swift is missing. Install Xcode, or run: xcode-select --install"
swift_major=$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -1)
(( ${swift_major:-0} >= 6 )) || die "SummonOS needs Swift 6 or newer (found: ${swift_major:-none}). Update Xcode."

# 2. The source: this checkout when run from one, else a clone in SUMMONOS_HOME.
here=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fi
if [[ -n $here && -d $here/incubator/summon && -d $here/macctl ]]; then
  ROOT="$here"
  say "Installing from this checkout: $ROOT"
else
  ROOT="${SUMMONOS_HOME:-$HOME/.summonos}"
  if [[ -d $ROOT/.git ]]; then
    say "Updating $ROOT"
    git -C "$ROOT" fetch --quiet origin "$REF"
    git -C "$ROOT" checkout --quiet "$REF"
    git -C "$ROOT" merge --quiet --ff-only FETCH_HEAD
  else
    say "Downloading SummonOS into $ROOT"
    git clone --quiet --depth 1 --branch "$REF" "$REPO" "$ROOT"
  fi
fi

mkdir -p "$BIN"

# 3. macctl: the settings CLI agents use to change the Mac (with snapshots and undo).
say "Building macctl"
swift build --package-path "$ROOT/macctl" -c release --scratch-path "$CACHE/macctl/build" --product macctl
cp "$(swift build --package-path "$ROOT/macctl" -c release --scratch-path "$CACHE/macctl/build" --show-bin-path)/macctl" "$BIN/macctl"

# 4. Summon: the menu app, the `summon` CLI, themes, skills and ~/Summon.
say "Building Summon"
"$ROOT/incubator/summon/scripts/bundle.sh" >/dev/null
"$ROOT/incubator/summon/scripts/install.sh"

# 5. Check the install.
say "Checking the install"
"$BIN/summon" doctor || true

cat <<EOF

  SummonOS is installed.
  Open Summon:      open ~/Applications/Summon.app   (or press ⌃⌥Space once it runs)
  Pick your agent:  summon default agent claude
  Settings CLI:     macctl list

  Powered by caffeine and questionable life choices.
EOF
# shellcheck disable=SC2016 # the export line is printed for the user to paste, unexpanded
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) printf '\n  Add %s to your PATH:  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc\n' "$BIN" ;;
esac
