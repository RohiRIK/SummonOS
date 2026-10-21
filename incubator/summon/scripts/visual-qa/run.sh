#!/bin/bash
# Visual QA on a GitHub-hosted macOS runner (.github/workflows/visual-qa.yml). Not for a personal Mac: it flips
# the system appearance, sends keystrokes and clicks, and screenshots the whole desktop into public artifacts.
# Needs Accessibility (osascript/System Events) and Screen Recording (screencapture) for bash and osascript,
# which the GitHub runner images pre-grant.
#   run.sh <out-dir> <Summon.app> <windows-helper> <tag>
# For light and dark: captures the menu bar, opens the launcher with ⌃⌥Space (falling back to `summon menu summon`,
# then `open -g summon://menu/`), opens the menu bar panel by clicking the status item, and captures each one.
# Then it runs `summon menu summon` once on its own. Every path tried goes to <out-dir>/<tag>-log.txt and the job
# summary. Exits 1 if anything did not open, did not close, failed to capture, or looks like the wrong theme.
set -uo pipefail

# Only on an ephemeral GitHub-hosted VM, unless explicitly overridden for a throwaway Mac.
if ! { [ "${GITHUB_ACTIONS:-}" = true ] && [ "${RUNNER_ENVIRONMENT:-}" = github-hosted ]; } && [ "${VQA_ALLOW_LOCAL:-}" != 1 ]; then
  echo "run.sh runs only on GitHub-hosted runners: it flips dark mode, drives the UI and screenshots the desktop (VQA_ALLOW_LOCAL=1 to override)" >&2
  exit 2
fi
OWNER=SummonMenu   # process name; CGWindowList reports the bundle name (Summon), so windows are matched by pid
if pgrep -x "$OWNER" >/dev/null; then
  echo "$OWNER is already running; refusing to test the wrong instance" >&2
  exit 2
fi

OUT=$1 APP=$2 WINDOWS=$3 TAG=$4
mkdir -p "$OUT"
LOG="$OUT/$TAG-log.txt"
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
PID=
fail=0
LIGHT_MIN=150 DARK_MAX=100   # mean luma of launcher and panel captures (spike: light 222-233, dark 29-46)

ORIGINAL_STYLE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)
cleanup() {
  local restore=false
  [ "$ORIGINAL_STYLE" = Dark ] && restore=true
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $restore" >/dev/null 2>&1
  [ -n "$PID" ] && kill "$PID" 2>/dev/null
}
trap cleanup EXIT

log() { echo "$*" | tee -a "$LOG"; }
failed() { echo "::error::$TAG: $*"; echo "FAIL: $*" >>"$LOG"; fail=1; }
warned() { echo "::warning::$TAG: $*"; echo "WARN: $*" >>"$LOG"; }
ids() { "$WINDOWS" "$PID" | awk '{print $1}' | sort; }
geometry() { "$WINDOWS" "$PID" | awk -v id="$1" '$1 == id {print $3, $4, $5, $6}'; }
width() { "$WINDOWS" "$PID" | awk -v id="$1" '$1 == id {print $5}'; }
is_open() { ids | grep -qx "$1"; }
keystroke() { osascript -e "tell application \"System Events\" to key code $1$2" >>"$LOG" 2>&1; }
click_status_item() {
  osascript -e "tell application \"System Events\" to tell process \"$OWNER\" to click menu bar item 1 of menu bar 2" >>"$LOG" 2>&1
}
oneline() { echo "$1" | tr '\n' ' ' | sed 's/ $//'; }

# Polls <command> every 0.5 s for up to <seconds>; returns its status.
wait_for() {
  local seconds=$1; shift
  local tries=$((seconds * 2))
  while [ "$tries" -gt 0 ]; do
    "$@" && return 0
    sleep 0.5
    tries=$((tries - 1))
  done
  "$@"
}

# New windows since <before> (a sorted id list), waiting up to 4 s for one to appear, then 0.5 s for stragglers.
opened_since() {
  local before=$1 now
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 0.5
    now=$(comm -13 <(echo "$before") <(ids))
    if [ -n "$now" ]; then
      sleep 0.5
      comm -13 <(echo "$before") <(ids)
      return
    fi
  done
}

# screencapture <args...> <file>, failing when it errors or writes nothing.
shot() {
  local file=${*: -1}
  if ! screencapture "$@" >>"$LOG" 2>&1 || [ ! -s "$file" ]; then
    failed "capture failed or empty: $(basename "$file")"
    return 1
  fi
}

# Fails unless the capture's mean luma matches <theme>.
check_luma() {
  local file=$1 theme=$2 luma
  luma=$("$WINDOWS" luma "$file") || { failed "could not measure $(basename "$file")"; return; }
  log "  luma $(basename "$file"): $luma"
  if [ "$theme" = light ] && [ "$luma" -le "$LIGHT_MIN" ]; then failed "$(basename "$file") too dark for light ($luma <= $LIGHT_MIN)"; fi
  if [ "$theme" = dark ] && [ "$luma" -ge "$DARK_MAX" ]; then failed "$(basename "$file") too bright for dark ($luma >= $DARK_MAX)"; fi
}

# Captures each window in <ids> by id (as <name>.png, or <name>-w<id>.png when several), plus the whole screen.
capture() {
  local name=$1 opened=$2 id file count
  [ -n "$opened" ] || failed "$name: no window to capture"
  count=$(echo "$opened" | grep -c . || true)
  for id in $opened; do
    file="$TAG-$name"; [ "$count" -gt 1 ] && file="$file-w$id"
    log "  window $id: $(geometry "$id") (x y w h) -> $file.png"
    shot -x -o -l"$id" "$OUT/$file.png"
  done
  shot -x "$OUT/$TAG-$name-screen.png"
}

# Expects exactly one new window of <width> in <opened>; anything else fails.
expect_one() {
  local what=$1 opened=$2 want=$3 id
  for id in $opened; do
    [ "$(width "$id")" = "$want" ] || failed "$what: unexpected extra window $id ($(geometry "$id"))"
  done
  [ "$(echo "$opened" | grep -c .)" -le 1 ] || failed "$what: opened $(echo "$opened" | grep -c .) windows, expected 1"
}

close_launcher() {
  local id=$1
  keystroke 53 ""   # Escape
  launcher_gone() { ! is_open "$id"; }
  if ! wait_for 3 launcher_gone; then
    # On macOS 26 runner, retry Escape or send toggle hotkey if initial Escape did not dismiss
    keystroke 49 " using {control down, option down}"
    wait_for 3 launcher_gone || failed "launcher window $id still open after Escape"
  fi
}

appearance() { defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light; }

read -r SCREEN_W SCREEN_H < <("$WINDOWS" screen)
log "screen ${SCREEN_W}x${SCREEN_H} points; $(sw_vers -productName) $(sw_vers -productVersion)"

open "$APP"
wait_for 30 pgrep -x "$OWNER" >/dev/null
PID=$(pgrep -x "$OWNER" | head -1)
log "SummonMenu pid: ${PID:-none}"
[ -n "$PID" ] || { failed "Summon did not start"; exit 1; }
HEALTH="$HOME/.local/state/summon/app.json"
# Ready once this instance has written its health file with ⌃⌥Space registered.
hotkey_ready() { grep -q "\"pid\" : $PID" "$HEALTH" 2>/dev/null && grep -q '"⌃⌥Space" : true' "$HEALTH"; }
wait_for 30 hotkey_ready || failed "app.json never showed ⌃⌥Space registered for pid $PID"
log "app health (hotkey registration): $(tr -d '\n' <"$HEALTH" 2>/dev/null || echo missing)"
log "windows at start (id layer x y w h):"; "$WINDOWS" "$PID" | tee -a "$LOG"

echo "## Visual QA: $TAG" >>"$SUMMARY"
for theme in light dark; do
  log "=== $theme ==="
  dark=false want=Light
  [ "$theme" = dark ] && dark=true want=Dark
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $dark" >>"$LOG" 2>&1
  appearance_is() { [ "$(appearance)" = "$want" ]; }
  wait_for 10 appearance_is || failed "appearance is $(appearance), expected $want"
  sleep 1   # let windows redraw in the new appearance
  log "appearance: $(appearance)"

  shot -x -R"0,0,$SCREEN_W,40" "$OUT/$TAG-$theme-menubar.png"
  shot -x "$OUT/$TAG-$theme-before-screen.png"
  log "windows before (id layer x y w h):"; "$WINDOWS" "$PID" | tee -a "$LOG"

  # Launcher: the hotkey first, then the documented fallbacks.
  path=none
  before=$(ids)
  log "try hotkey: osascript key code 49 using {control down, option down}"
  keystroke 49 " using {control down, option down}"
  opened=$(opened_since "$before")
  if [ -n "$opened" ]; then
    path=hotkey
  else
    log "  hotkey opened no window"
    log "try fallback: summon menu summon"
    "$APP/Contents/MacOS/summon" menu summon >>"$LOG" 2>&1
    opened=$(opened_since "$before")
    if [ -n "$opened" ]; then
      path=summon-menu-summon
    else
      log "  summon menu summon opened no window"
      log "try fallback: open -g summon://menu/"
      open -g "summon://menu/" >>"$LOG" 2>&1
      opened=$(opened_since "$before")
      [ -n "$opened" ] && path=open-summon-url
    fi
  fi
  log "launcher path used ($theme): $path"
  echo "- $theme launcher: opened by **$path**" >>"$SUMMARY"
  [ "$path" = none ] && failed "$theme launcher did not open"
  [ "$path" = hotkey ] && expect_one "$theme launcher" "$opened" 620
  capture "$theme-launcher" "$opened"
  [ -s "$OUT/$TAG-$theme-launcher.png" ] && check_luma "$OUT/$TAG-$theme-launcher.png" "$theme"
  for id in $opened; do [ "$(width "$id")" = 620 ] && close_launcher "$id"; done

  # Menu bar panel (MenuBarExtra): click the status item through Accessibility. There is no coordinate-click
  # fallback: on macOS 26 the status item is not a window of the app's pid, so there is nothing to aim at.
  before=$(ids)
  ppath=none opened=""
  log "try panel: System Events click menu bar item 1 of menu bar 2 of process $OWNER"
  if click_status_item; then
    opened=$(opened_since "$before")
    [ -n "$opened" ] && ppath=accessibility-click
  fi
  log "panel path used ($theme): $ppath"
  echo "- $theme menu bar panel: opened by **$ppath**" >>"$SUMMARY"
  [ "$ppath" = none ] && failed "$theme panel did not open"
  expect_one "$theme panel" "$opened" 300
  capture "$theme-panel" "$opened"
  [ -s "$OUT/$TAG-$theme-panel.png" ] && check_luma "$OUT/$TAG-$theme-panel.png" "$theme"
  # Escape does not close a MenuBarExtra window; a second click on the status item does.
  for id in $opened; do
    click_status_item
    panel_gone() { ! is_open "$id"; }
    if wait_for 3 panel_gone; then log "  panel closed"; else failed "$theme panel window $id still open after a second click"; fi
  done
done

# The fallback path on its own, so the artifacts show it works too (in light, the hotkey already did the job).
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >>"$LOG" 2>&1
want=Light
wait_for 10 appearance_is || failed "appearance did not return to Light for the fallback check"
sleep 1
log "=== fallback check (light): summon menu summon ==="
before=$(ids)
"$APP/Contents/MacOS/summon" menu summon >>"$LOG" 2>&1
opened=$(opened_since "$before")
log "summon menu summon opened: $(oneline "${opened:-nothing}")"
echo "- fallback check: \`summon menu summon\` opened $(oneline "${opened:-nothing}")" >>"$SUMMARY"
[ -n "$opened" ] || failed "summon menu summon opened nothing"
launcher="" activity=""
for id in $opened; do
  case "$(width "$id")" in
    620) launcher=$id ;;
    980) activity=$id ;;
    *) failed "summon menu summon: unexpected window $id ($(geometry "$id"))" ;;
  esac
done
[ -n "$opened" ] && [ -z "$launcher" ] && failed "summon menu summon did not open the launcher"
# Known app bug (not fixed here): the summon:// URL also opens the Activity window. A warning until that lands.
[ -n "$activity" ] && warned "known bug: summon menu summon also opened the Summon Activity window ($activity)"
capture "light-fallback-cli" "$opened"
[ -n "$launcher" ] && close_launcher "$launcher"
if [ -n "$activity" ]; then
  osascript -e "tell application \"System Events\" to tell process \"$OWNER\" to click (first button of window \"Summon Activity\" whose subrole is \"AXCloseButton\")" >>"$LOG" 2>&1
  activity_gone() { ! is_open "$activity"; }
  if wait_for 3 activity_gone; then log "  Activity window closed"; else warned "Activity window $activity still open (the exit trap quits Summon)"; fi
fi

log "files:"; ls -l "$OUT" >>"$LOG"
log "RESULT fail=$fail"
echo "- result: $([ "$fail" = 0 ] && echo pass || echo '**FAIL**')" >>"$SUMMARY"
{ echo '```'; cat "$LOG"; echo '```'; } >>"$SUMMARY"
exit "$fail"
