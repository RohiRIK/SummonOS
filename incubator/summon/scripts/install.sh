#!/bin/bash
# Stage and verify the app and optional macctl before replacing any live executable.
# SUMMONOS_MACCTL_SOURCE is passed by the workspace installer after both builds finish.
# SUMMONOS_APP_SOURCE (default build/Summon.app) is the unpacked release app when installing a release.
set -euo pipefail
cd "$(dirname "$0")/.."

verify_only=0
if [[ $# -eq 1 && $1 == --verify-only ]]; then
  verify_only=1
elif [[ $# -ne 0 ]]; then
  echo "usage: $0 [--verify-only]" >&2; exit 2
fi
APP="${SUMMONOS_APP_SOURCE:-build/Summon.app}"
DEST="$HOME/Applications/Summon.app"
BIN="$HOME/.local/bin"
[[ -d $APP && -x $APP/Contents/MacOS/summon && -x $APP/Contents/MacOS/SummonMenu ]] || {
  echo "Run scripts/bundle.sh first: both app executables are required." >&2; exit 1;
}
if [[ $verify_only -eq 0 ]]; then
  [[ ! -L $DEST ]] || { echo "Refusing to replace a symlink at $DEST." >&2; exit 1; }
fi
APP_STAGE='' BIN_STAGE='' LOCK=''
app_changed=0 cli_changed=0 macctl_changed=0 committed=0
cleanup() {
  local result=$? rollback_failed=0 cleanup_failed=0
  trap - EXIT INT TERM
  set +e
  if [[ $committed -eq 0 ]]; then
    if [[ -n $BIN_STAGE && ( -e $BIN_STAGE/previous-macctl || -L $BIN_STAGE/previous-macctl ) ]]; then
      rm -f "$BIN/macctl" && mv "$BIN_STAGE/previous-macctl" "$BIN/macctl" || rollback_failed=1
    elif [[ $macctl_changed -eq 1 ]]; then
      rm -f "$BIN/macctl" || rollback_failed=1
    fi
    if [[ -n $BIN_STAGE && ( -e $BIN_STAGE/previous-summon || -L $BIN_STAGE/previous-summon ) ]]; then
      rm -f "$BIN/summon" && mv "$BIN_STAGE/previous-summon" "$BIN/summon" || rollback_failed=1
    elif [[ $cli_changed -eq 1 ]]; then
      rm -f "$BIN/summon" || rollback_failed=1
    fi
    if [[ -n $APP_STAGE && -e $APP_STAGE/previous.app ]]; then
      rm -rf "$DEST" && mv "$APP_STAGE/previous.app" "$DEST" || rollback_failed=1
    elif [[ $app_changed -eq 1 ]]; then
      rm -rf "$DEST" || rollback_failed=1
    fi
    if [[ $rollback_failed -eq 1 ]]; then
      echo "Automatic recovery incomplete; previous files retained in $APP_STAGE and $BIN_STAGE. Restore before retrying." >&2
    elif [[ $result -ne 0 ]]; then
      echo "Install failed; previous app and commands restored. Added themes/configuration were retained." >&2
    fi
  fi
  if [[ $rollback_failed -eq 0 ]]; then
    [[ -z $APP_STAGE ]] || rm -rf "$APP_STAGE" || cleanup_failed=1
    [[ -z $BIN_STAGE ]] || rm -rf "$BIN_STAGE" || cleanup_failed=1
  fi
  [[ -z $LOCK ]] || rmdir "$LOCK" || cleanup_failed=1
  if [[ $cleanup_failed -eq 1 ]]; then echo "Install cleanup failed; inspect owned staging and lock paths." >&2; fi
  if [[ $result -eq 0 && ( $rollback_failed -eq 1 || $cleanup_failed -eq 1 ) ]]; then result=1; fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

VERIFY="$(cd ../.. && pwd -P)/tools/build-metadata.py"
[[ -f $VERIFY ]] || VERIFY="$(dirname "$0")/build-metadata.py"
[[ -f $VERIFY ]] || { echo "Missing packaged build-metadata.py validator" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
if [[ -n ${SUMMONOS_MACCTL_SOURCE:-} ]]; then
  [[ -x $SUMMONOS_MACCTL_SOURCE ]] || { echo "Built macctl executable is missing." >&2; exit 1; }
  if codesign -dv "$SUMMONOS_MACCTL_SOURCE" >/dev/null 2>&1; then
    codesign --verify --strict "$SUMMONOS_MACCTL_SOURCE"
  fi
fi
verify_args=(--manifest "$APP/Contents/Resources/BuildInfo.json" --app "$APP" --summon "$APP/Contents/MacOS/summon")
[[ -z ${SUMMONOS_MACCTL_SOURCE:-} ]] || verify_args+=(--macctl "$SUMMONOS_MACCTL_SOURCE")
python3 "$VERIFY" verify "${verify_args[@]}"
"$APP/Contents/MacOS/summon" commands --json >/dev/null
if [[ $verify_only -eq 1 ]]; then echo "Validated supplied app and CLI; no live files changed."; exit 0; fi

mkdir -p "$HOME/Applications" "$BIN"
LOCK="$HOME/Applications/.summon-install.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  LOCK=
  echo "Install lock exists; check for another installer before removing a stale lock." >&2
  exit 1
fi
APP_STAGE=$(mktemp -d "$HOME/Applications/.summon-install.XXXXXX")
BIN_STAGE=$(mktemp -d "$BIN/.summon-install.XXXXXX")

cp -R "$APP" "$APP_STAGE/Summon.app"
codesign --verify --deep --strict "$APP_STAGE/Summon.app"
python3 "$VERIFY" verify --manifest "$APP_STAGE/Summon.app/Contents/Resources/BuildInfo.json" \
  --app "$APP_STAGE/Summon.app" --summon "$APP_STAGE/Summon.app/Contents/MacOS/summon"
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
verify_args=(--manifest "$DEST/Contents/Resources/BuildInfo.json" --app "$DEST" --summon "$DEST/Contents/MacOS/summon")
[[ -z ${SUMMONOS_MACCTL_SOURCE:-} ]] || verify_args+=(--macctl "$BIN/macctl")
python3 "$VERIFY" verify "${verify_args[@]}"
"$BIN/summon" commands --json >/dev/null

mkdir -p "$HOME/.config/summon/themes" "$HOME/Summon"
for dir in "$APP"/Contents/share/summon/themes/*/; do
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
