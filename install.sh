#!/bin/bash
# SummonOS installer: Summon (app + `summon` CLI + themes + skills) and macctl.
#
#   curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --version v0.1.0     # pass options after `bash -s --`
#   curl -fsSL .../install.sh | bash -s -- --channel edge       # the rolling build of the newest green main
#   ./install.sh                     # from a checkout: builds and installs that checkout
#
# Piped from curl, it downloads the newest GitHub release (prereleases included, never the rolling `edge`), checks it against
# SHA256SUMS and installs it: no Xcode needed. With no release published yet it builds from source instead.
#
# Options:
#   --from-source     build from source (needs git and Swift 6: Xcode or the Command Line Tools)
#   --version vX.Y.Z  install that release
#   --channel C       stable (default: the newest release tag) or edge (rebuilt from every green main)
#   --connect         after the install, run `summon connect` without asking
#   --yes             never prompt (does not connect unless --connect is also given)
#
# Environment:
#   SUMMONOS_HOME   where the source checkout lives for --from-source (default ~/.summonos)
#   SUMMONOS_REF    branch or tag to build with --from-source (default main)
#
# Safe to run again: it replaces the app and commands with rollback, and keeps your themes, projects and settings.
# Needs macOS 15+.
set -euo pipefail

REPO="https://github.com/RohiRIK/SummonOS.git"
API="https://api.github.com/repos/RohiRIK/SummonOS"
DOWNLOAD="https://github.com/RohiRIK/SummonOS/releases/download"
REF="${SUMMONOS_REF:-main}"
BIN="$HOME/.local/bin"
CACHE="$HOME/Library/Caches/macplugins"

say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

FROM_SOURCE=0 TAG="" CHANNEL=stable CONNECT=0 YES=0
while (( $# )); do
  case "$1" in
    --from-source) FROM_SOURCE=1 ;;
    --version) [[ -n ${2:-} ]] || die "--version needs a tag, such as v0.1.0"; TAG=$2; shift ;;
    --version=*) TAG=${1#--version=} ;;
    --channel) [[ -n ${2:-} ]] || die "--channel needs stable or edge"; CHANNEL=$2; shift ;;
    --channel=*) CHANNEL=${1#--channel=} ;;
    --connect) CONNECT=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help) echo "usage: install.sh [--from-source | --version vX.Y.Z | --channel stable|edge] [--connect] [--yes]"; exit 0 ;;
    *) die "Unknown option: $1 (see the options at the top of install.sh)" ;;
  esac
  shift
done
(( FROM_SOURCE == 0 || ${#TAG} == 0 )) || die "Choose either --from-source or --version, not both."
case $CHANNEL in
  stable) ;;
  edge) (( FROM_SOURCE == 0 && ${#TAG} == 0 )) || die "--channel edge cannot be combined with --from-source or --version."; TAG=edge ;;
  *) die "Unknown channel: $CHANNEL (expected stable or edge)" ;;
esac
[[ -z $TAG || $TAG == edge || $TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "Not a release tag: $TAG (expected vX.Y.Z)"

# 1. This Mac can run it.
[[ $(uname -s) == Darwin ]] || die "SummonOS runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 15 )) || die "SummonOS needs macOS 15 or newer (this Mac has $(sw_vers -productVersion))."

# 2. Where it comes from: a checkout builds itself; otherwise a release, or source with --from-source.
here=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fi
in_checkout=0
[[ -n $here && -d $here/incubator/summon && -d $here/macctl ]] && in_checkout=1
if (( FROM_SOURCE == 0 && ${#TAG} == 0 && in_checkout == 0 )); then
  # /releases lists newest first and includes prereleases (/releases/latest skips them); the rolling `edge` is opt-in.
  TAG=$(curl -fsSL "$API/releases?per_page=30" 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/' | grep -vx edge | sed -n 1p) || TAG=""
  if [[ -z $TAG ]]; then
    say "No SummonOS release is published yet (or GitHub is unreachable); building from source instead."
    FROM_SOURCE=1
  elif [[ ! $TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    die "GitHub returned an unexpected release tag: $TAG"
  fi
fi

install_release() {
  local version=${TAG#v} name
  WORK=$(mktemp -d)
  trap '/bin/rm -rf "$WORK"' EXIT
  curl -fsSL --retry 3 -o "$WORK/SHA256SUMS" "$DOWNLOAD/$TAG/SHA256SUMS" || die "Could not download SHA256SUMS from release $TAG."
  if [[ $TAG == edge ]]; then
    # The rolling edge zip is named after its build (summonos-0.1.0-edge.<sha>-...), so SHA256SUMS names it.
    name=$(awk '{ sub(/^\*/, "", $2) } $2 ~ /^summonos-.*-macos-universal\.zip$/ { print $2; exit }' "$WORK/SHA256SUMS")
    version=${name#summonos-}
    version=${version%-macos-universal.zip}
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+-edge\.[0-9a-f]+$ ]] || die "The edge release does not list a SummonOS build."
  fi
  name="summonos-$version-macos-universal.zip"
  say "Downloading SummonOS $version"
  curl -fsSL --retry 3 -o "$WORK/$name" "$DOWNLOAD/$TAG/$name" || die "Could not download $name from release $TAG."
  local expected actual
  expected=$(awk -v f="$name" '$2 == f || $2 == "*" f { print $1; exit }' "$WORK/SHA256SUMS")
  actual=$(shasum -a 256 "$WORK/$name" | cut -d' ' -f1)
  [[ -n $expected && $actual == "$expected" ]] || die "Checksum mismatch for $name: refusing to install it."
  say "Checksum verified"
  ditto -x -k "$WORK/$name" "$WORK/unpacked"
  local package="$WORK/unpacked/summonos-$version"
  [[ -d $package/Summon.app && -x $package/bin/macctl && -f $package/scripts/install.sh ]] \
    || die "The release archive does not have the expected layout."
  SUMMONOS_APP_SOURCE="$package/Summon.app" SUMMONOS_MACCTL_SOURCE="$package/bin/macctl" \
    bash "$package/scripts/install.sh"
}

install_source() {
  command -v git >/dev/null || die "git is missing. Install the Command Line Tools: xcode-select --install"
  command -v swift >/dev/null || die "Swift is missing. Install Xcode, or run: xcode-select --install"
  swift_major=$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -1)
  (( ${swift_major:-0} >= 6 )) || die "SummonOS needs Swift 6 or newer (found: ${swift_major:-none}). Update Xcode."

  if (( in_checkout )); then
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

  # macctl: the settings CLI agents use to change the Mac (with snapshots and undo).
  say "Building macctl"
  swift build --package-path "$ROOT/macctl" -c release --scratch-path "$CACHE/macctl/build" --product macctl
  MACCTL_SOURCE="$(swift build --package-path "$ROOT/macctl" -c release --scratch-path "$CACHE/macctl/build" --show-bin-path)/macctl"

  # Summon: the menu app, the `summon` CLI, themes, skills and ~/Summon.
  say "Building Summon"
  "$ROOT/incubator/summon/scripts/bundle.sh" >/dev/null
  SUMMONOS_MACCTL_SOURCE="$MACCTL_SOURCE" "$ROOT/incubator/summon/scripts/install.sh"
}

# 3. Install: both paths stage the app and commands and roll back on failure (incubator/summon/scripts/install.sh).
if [[ -n $TAG ]]; then install_release; else install_source; fi

# 4. Check the install.
say "Checking the install"
if ! "$BIN/summon" doctor; then
  die "Files were installed, but summon doctor found failed checks. Review the output and run summon doctor again after resolving them."
fi

# 5. Optionally connect the installed agents (the summon MCP server and a This Mac note; files are backed up).
commands=$("$BIN/summon" commands --json 2>/dev/null || true)
if [[ $commands == *'"connect"'* ]]; then
  connect=$CONNECT
  # Ask only on a terminal; stdin is the script itself under `curl | bash`, so read the answer from /dev/tty.
  if (( ! connect && ! YES )) && [[ -t 1 ]] && { : </dev/tty; } 2>/dev/null; then
    printf '\n  Connect your coding agents to this Mac? summon connect adds the summon MCP server and a\n'
    printf '  This Mac note to Claude Code, Codex, Cursor, OpenCode and the other agents installed here,\n'
    printf '  backing up each file first (preview: summon connect --dry-run). [y/N] '
    answer=""
    read -r answer </dev/tty || answer=""
    [[ $answer == [yY]* ]] && connect=1
  fi
  if (( connect )); then
    say "Connecting your agents"
    "$BIN/summon" connect || printf '\033[1;33mwarning:\033[0m summon connect failed; run it again later.\n' >&2
  else
    printf '\n  Connect your agents later with: summon connect\n'
  fi
fi

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
