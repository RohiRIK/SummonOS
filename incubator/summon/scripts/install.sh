#!/bin/bash
# Stage and verify the app and optional macctl before replacing any live executable.
# SUMMONOS_MACCTL_SOURCE is passed by the workspace installer after both builds finish.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Summon.app"
DEST="$HOME/Applications/Summon.app"
BIN="$HOME/.local/bin"
[[ -d $APP && -x $APP/Contents/MacOS/summon && -x $APP/Contents/MacOS/SummonMenu ]] || {
  echo "Run scripts/bundle.sh first: both app executables are required." >&2; exit 1;
}
[[ ! -L $DEST ]] || { echo "Refusing to replace a symlink at $DEST." >&2; exit 1; }
mkdir -p "$HOME/Applications" "$BIN"
LOCK="$HOME/Applications/.summon-install.lock"
mkdir "$LOCK" 2>/dev/null || {
  echo "Install lock exists at $LOCK. Check for another installer; remove a stale lock only after it has stopped." >&2
  exit 1
}
trap 'rmdir "$LOCK"' EXIT
APP_STAGE=$(mktemp -d "$HOME/Applications/.summon-install.XXXXXX")
BIN_STAGE=$(mktemp -d "$BIN/.summon-install.XXXXXX")
app_changed=0
cli_changed=0
macctl_changed=0
committed=0
cleanup() {
  result=$?
  trap - EXIT
  set +e
  rollback_failed=0
  if [[ $committed -eq 0 ]]; then
    if [[ -e $BIN_STAGE/previous-macctl || -L $BIN_STAGE/previous-macctl ]]; then
      rm -f "$BIN/macctl" && mv "$BIN_STAGE/previous-macctl" "$BIN/macctl" || rollback_failed=1
    elif [[ $macctl_changed -eq 1 ]]; then
      rm -f "$BIN/macctl" || rollback_failed=1
    fi
    if [[ -e $BIN_STAGE/previous-summon || -L $BIN_STAGE/previous-summon ]]; then
      rm -f "$BIN/summon" && mv "$BIN_STAGE/previous-summon" "$BIN/summon" || rollback_failed=1
    elif [[ $cli_changed -eq 1 ]]; then
      rm -f "$BIN/summon" || rollback_failed=1
    fi
    if [[ -e $APP_STAGE/previous.app ]]; then
      rm -rf "$DEST" && mv "$APP_STAGE/previous.app" "$DEST" || rollback_failed=1
    elif [[ $app_changed -eq 1 ]]; then
      rm -rf "$DEST" || rollback_failed=1
    fi
    if [[ $rollback_failed -eq 1 ]]; then
      echo "Install and automatic recovery failed. Previous files retained in $APP_STAGE and $BIN_STAGE; restore them before retrying." >&2
      rmdir "$LOCK"
      exit 1
    fi
    echo "Install failed; previous app and commands restored. Any added themes/configuration were retained." >&2
  fi
  rm -rf "$APP_STAGE" "$BIN_STAGE"
  rmdir "$LOCK"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cp -R "$APP" "$APP_STAGE/Summon.app"
codesign --verify --deep --strict "$APP_STAGE/Summon.app"
"$APP_STAGE/Summon.app/Contents/MacOS/summon" commands --json >/dev/null
ln -s "$DEST/Contents/MacOS/summon" "$BIN_STAGE/summon"
if [[ -n ${SUMMONOS_MACCTL_SOURCE:-} ]]; then
  [[ -x $SUMMONOS_MACCTL_SOURCE ]] || { echo "Built macctl executable is missing." >&2; exit 1; }
  cp "$SUMMONOS_MACCTL_SOURCE" "$BIN_STAGE/macctl"
  "$BIN_STAGE/macctl" --help >/dev/null
fi
for command_name in summon macctl; do
  [[ ! -d $BIN/$command_name || -L $BIN/$command_name ]] || {
    echo "Refusing to replace directory $BIN/$command_name." >&2; exit 1;
  }
done

# Retain originals until initialization succeeds. Moves stay on the destination's filesystem.
[[ ! -e $DEST ]] || mv "$DEST" "$APP_STAGE/previous.app"
app_changed=1
mv "$APP_STAGE/Summon.app" "$DEST"
[[ ! -e $BIN/summon && ! -L $BIN/summon ]] || mv "$BIN/summon" "$BIN_STAGE/previous-summon"
cli_changed=1
mv "$BIN_STAGE/summon" "$BIN/summon"
if [[ -n ${SUMMONOS_MACCTL_SOURCE:-} ]]; then
  [[ ! -e $BIN/macctl && ! -L $BIN/macctl ]] || mv "$BIN/macctl" "$BIN_STAGE/previous-macctl"
  macctl_changed=1
  mv "$BIN_STAGE/macctl" "$BIN/macctl"
fi

mkdir -p "$HOME/.config/summon/themes" "$HOME/Summon"
for dir in themes/*/; do
  [[ -d $dir ]] || continue
  slug=$(basename "$dir")
  [[ -e "$HOME/.config/summon/themes/$slug" ]] || cp -R "$dir" "$HOME/.config/summon/themes/$slug"
done
"$BIN/summon" menu init >/dev/null
"$BIN/summon" skills link
"$BIN/summon" home
if [[ -n ${SUMMONOS_MACCTL_SOURCE:-} ]]; then
  python3 scripts/install-state.py record --macctl
else
  python3 scripts/install-state.py record
fi
committed=1
echo "Installed. Open ~/Applications/Summon.app, then choose an agent: summon default agent claude"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Add ~/.local/bin to your PATH to use summon in a terminal." ;;
esac
