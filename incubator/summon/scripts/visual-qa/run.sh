#!/bin/bash
# Visual QA on a GitHub-hosted macOS runner (.github/workflows/visual-qa.yml). Not for a personal Mac: it flips
# the system appearance and opens Summon's launcher and menu bar panel.
#   run.sh <out-dir> <Summon.app> <windows-helper> <tag>
# For light and dark: captures the menu bar, opens the launcher with ⌃⌥Space (falling back to `summon menu summon`,
# then `open -g summon://menu/`), opens the menu bar panel by clicking the status item, and captures each one.
# Every path tried and whether it opened a window goes to <out-dir>/<tag>-log.txt and the job summary.
set -uo pipefail

OUT=$1 APP=$2 WINDOWS=$3 TAG=$4
mkdir -p "$OUT"
LOG="$OUT/$TAG-log.txt"
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
OWNER=SummonMenu

log() { echo "$*" | tee -a "$LOG"; }
ids() { "$WINDOWS" "$OWNER" | awk '{print $1}' | sort; }
geometry() { "$WINDOWS" "$OWNER" | awk -v id="$1" '$1 == id {print $3, $4, $5, $6}'; }
keystroke() { osascript -e "tell application \"System Events\" to key code $1$2" 2>&1 | tee -a "$LOG"; }

# New SummonMenu windows since <before> (a sorted id list), waiting up to 4 s for one to appear.
opened_since() {
  local before=$1 now
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 0.5
    now=$(comm -13 <(echo "$before") <(ids))
    if [ -n "$now" ]; then echo "$now"; return; fi
  done
}

# Captures each window in <ids> by id, plus the whole screen, as <name>.png and <name>-screen.png.
capture() {
  local name=$1 opened=$2 id
  for id in $opened; do
    log "  window $id: $(geometry "$id") (x y w h)"
    screencapture -x -o -l"$id" "$OUT/$TAG-$name.png" 2>&1 | tee -a "$LOG"
  done
  screencapture -x "$OUT/$TAG-$name-screen.png" 2>&1 | tee -a "$LOG"
}

close_launcher() {
  keystroke 53 ""   # Escape
  sleep 1
}

read -r SCREEN_W SCREEN_H < <("$WINDOWS" screen)
log "screen ${SCREEN_W}x${SCREEN_H} points; $(sw_vers -productName) $(sw_vers -productVersion)"

open "$APP"
for _ in $(seq 1 30); do pgrep -x "$OWNER" >/dev/null && break; sleep 1; done
sleep 5
log "SummonMenu pid: $(pgrep -x "$OWNER" || echo none)"
log "app health (hotkey registration): $(tr -d '\n' <"$HOME/.local/state/summon/app.json" 2>/dev/null || echo missing)"
log "windows at start (id layer x y w h):"; "$WINDOWS" "$OWNER" | tee -a "$LOG"

echo "## Visual QA: $TAG" >>"$SUMMARY"
for theme in light dark; do
  log "=== $theme ==="
  dark=false; [ "$theme" = dark ] && dark=true
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $dark" 2>&1 | tee -a "$LOG"
  sleep 3
  log "appearance: $(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"

  screencapture -x -R"0,0,$SCREEN_W,40" "$OUT/$TAG-$theme-menubar.png" 2>&1 | tee -a "$LOG"

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
    "$APP/Contents/MacOS/summon" menu summon 2>&1 | tee -a "$LOG"
    opened=$(opened_since "$before")
    if [ -n "$opened" ]; then
      path=summon-menu-summon
    else
      log "  summon menu summon opened no window"
      log "try fallback: open -g summon://menu/"
      open -g "summon://menu/" 2>&1 | tee -a "$LOG"
      opened=$(opened_since "$before")
      [ -n "$opened" ] && path=open-summon-url
    fi
  fi
  log "launcher path used ($theme): $path"
  echo "- $theme launcher: opened by **$path**" >>"$SUMMARY"
  capture "$theme-launcher" "$opened"
  close_launcher

  # Menu bar panel (MenuBarExtra): click the status item through Accessibility, else at its window's centre.
  before=$(ids)
  ppath=none
  log "try panel: System Events click menu bar item 1 of menu bar 2 of process $OWNER"
  if osascript -e "tell application \"System Events\" to tell process \"$OWNER\" to click menu bar item 1 of menu bar 2" >>"$LOG" 2>&1; then
    opened=$(opened_since "$before")
    [ -n "$opened" ] && ppath=accessibility-click
  fi
  if [ -z "${opened:-}" ] || [ "$ppath" = none ]; then
    item=$("$WINDOWS" "$OWNER" | awk '$2 == 25 && $4 == 0 {print $3 + $5 / 2, $4 + $6 / 2; exit}')
    if [ -n "$item" ]; then
      log "try panel: CGEvent click at status item centre $item"
      # shellcheck disable=SC2086 # two coordinates on purpose
      "$WINDOWS" click $item 2>&1 | tee -a "$LOG"
      opened=$(opened_since "$before")
      [ -n "$opened" ] && ppath=cgevent-click
    else
      log "  no status item window found"
    fi
  fi
  log "panel path used ($theme): $ppath"
  echo "- $theme menu bar panel: opened by **$ppath**" >>"$SUMMARY"
  capture "$theme-panel" "${opened:-}"
  keystroke 53 ""
  sleep 1
  opened=""
done

osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' >/dev/null 2>&1
log "files:"; ls -l "$OUT" | tee -a "$LOG"
echo '```' >>"$SUMMARY"; cat "$LOG" >>"$SUMMARY"; echo '```' >>"$SUMMARY"
