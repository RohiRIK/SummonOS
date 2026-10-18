#!/bin/sh
# Passes the Claude Code hook payload (JSON on stdin) to `summon event hook <start|end>`.
# Never blocks or fails the session: a missing summon is silently skipped.
summon_bin=$(command -v summon 2>/dev/null)
for candidate in "$HOME/.local/bin/summon" "$HOME/Applications/Summon.app/Contents/MacOS/summon" "/Applications/Summon.app/Contents/MacOS/summon"; do
  [ -n "$summon_bin" ] && break
  [ -x "$candidate" ] && summon_bin="$candidate"
done
[ -n "$summon_bin" ] || exit 0
"$summon_bin" event hook "$1" >/dev/null 2>&1 || true
exit 0
