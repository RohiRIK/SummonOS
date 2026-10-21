#!/bin/bash
# TEMPORARY (PR #61): does a summon:// open show the Activity window? check.sh <variant> <out> <windows-helper>
set -uo pipefail
V=$1 OUT=$2 W=$3
APP="$PWD/incubator/summon/build/Summon.app"
CLI="$APP/Contents/MacOS/summon"
LOG="$OUT/$V-log.txt"
mkdir -p "$OUT"
log() { echo "$*" | tee -a "$LOG"; }
pid() { pgrep -x SummonMenu | head -1; }
front() { osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>&1; }
axwins() { osascript -e 'tell application "System Events" to tell process "SummonMenu" to get name of every window' 2>&1; }
quit_app() { pkill -x SummonMenu; for _ in $(seq 1 20); do pgrep -x SummonMenu >/dev/null || return; sleep 0.5; done; pkill -9 -x SummonMenu; sleep 1; }
start_app() { open "$APP"; for _ in $(seq 1 30); do [ -n "$(pid)" ] && break; sleep 1; done; sleep 5; }
finder_front() { osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1; sleep 1.5; }

# check <name> <before-window-list>: verdict for the windows that appeared since <before>
check() {
  local name=$1 before=$2 now new activity=no panel=no
  sleep 3
  now=$("$W" "$(pid)")
  new=$(comm -13 <(echo "$before" | sort) <(echo "$now" | sort))
  log "[$V/$name] new windows (id layer x y w h name):"; log "${new:-  (none)}"
  log "[$V/$name] all windows:"; log "$now"
  log "[$V/$name] AX window names: $(axwins)"
  while read -r _ layer _ _ w h title; do
    [ -z "${w:-}" ] && continue
    if [ "$w" -ge 900 ] && [ "$h" -ge 600 ] || [[ "$title" == *Activity* ]]; then activity=yes; fi
    [ "$w" -eq 360 ] && panel=yes
  done <<<"$new"
  echo "$now" | awk '$5 >= 900 && $6 >= 600' | grep -q . && activity=yes
  screencapture -x "$OUT/$V-$name.png"
  log "RESULT variant=$V action=$name activity_window=$activity panel=$panel frontmost=$(front)"
}

log "=== variant $V on $(sw_vers -productName) $(sw_vers -productVersion) ==="
quit_app
start_app
log "pid $(pid); windows at start:"; "$W" "$(pid)" | tee -a "$LOG"

finder_front; b=$("$W" "$(pid)"); "$CLI" panel 2>&1 | tee -a "$LOG"; check summon-panel "$b"
open -g summon://panel/close; sleep 1
finder_front; b=$("$W" "$(pid)"); open -g summon://panel; check open-g-panel "$b"
open -g summon://panel/close; sleep 1
finder_front; b=$("$W" "$(pid)"); "$CLI" menu summon 2>&1 | tee -a "$LOG"; check summon-menu-summon "$b"
open -g summon://panel/close; sleep 1

# Cold launch: Summon not running, a menu URL launches it and must open the panel only.
quit_app; finder_front
open -g summon://menu/
for _ in $(seq 1 30); do [ -n "$(pid)" ] && break; sleep 1; done
sleep 2
check cold-open-g-menu ""
quit_app
