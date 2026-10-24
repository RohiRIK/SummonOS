---
name: diagnose-crash-mac
description: >
  Diagnose why an app or process crashed, hung, or was killed on this Mac, from a macOS
  diagnostic report (.ips, .crash, .hang, .panic). Use when a Summon crash alert or notification
  is acted on (Diagnose with AI), when asked why an app quit unexpectedly, keeps crashing, beachballs, or the Mac
  restarted on its own. Triggers: crash, quit unexpectedly, EXC_BAD_ACCESS, SIGSEGV, SIGABRT,
  hang, spin, kernel panic, jetsam, DiagnosticReports, "why did X crash".
---

# Diagnosing a crash on macOS

Work from evidence. The goal is an honest account of what happened, not a plausible story.

## Find the report

| Kind | Where |
|---|---|
| App and process crashes, hangs (`.ips`) | `~/Library/Logs/DiagnosticReports/` (yours), `/Library/Logs/DiagnosticReports/` (system, needs admin to read some) |
| Kernel panics | `/Library/Logs/DiagnosticReports/panic-full-*.panic` or `Kernel-*.ips` |
| Memory kills (jetsam) | `JetsamEvent-*.ips` |

`summon crash list` lists recent reports newest first; `summon crash diagnose <file>` hands one to you with the facts.

## Read the report

An `.ips` file is two JSON documents: line 1 is a small header (`app_name`, `app_version`,
`bug_type`, `timestamp`, `incident_id`), the rest is the body. Useful body keys:

- `procName`, `procPath`, `pid`, `parentProc`: what died and who launched it.
- `exception` (`type`, `signal`, `subtype`, `codes`) and `termination` (`namespace`, `indicator`, `reasons`).
  `CODESIGNING` or `Namespace SIGNAL, Code 9` from `launchd` mean the system killed it, not a bug in its code.
- `faultingThread` and `threads[n].frames`: the crashing stack; `usedImages` maps frame
  `imageIndex` to binaries. Other threads show what work was in flight.
- `asi` / `lastExceptionBacktrace` for ObjC/Swift exceptions: the message often names the cause outright.

`bug_type` tells the kind: 309 crash, 298 jetsam (memory kill), 288 stackshot (hang/spin), 210 panic. The file
name says it too (`<App>-…ips`, `JetsamEvent-…`, `….hang`, `….spin`, `panic-full-…`); when they disagree, trust the body.

## Rule out the boring causes first

1. **Memory pressure:** `memory_pressure`, `vm_stat`, recent `JetsamEvent` reports. A jetsam kill is not a bug in that app.
2. **Disk full:** `df -h /`.
3. **Recent change:** `ls -lt "$(brew --prefix)/Cellar"/*/ | head` (recent Homebrew installs),
   `softwareupdate --history | head`, the app's version in the header vs. earlier reports, and
   `summon checkpoint list` for what an agent changed recently.
4. **Code signing / quarantine:** `codesign -dv --verbose=2 <app>`, `spctl -a -vv <app>`, `xattr -l <app>`.

## Correlate against the timeline

The crash timestamp is the most underused evidence. Look around it in the unified log, time-boxed:

```bash
log show --start "2026-10-17 22:14:00" --end "2026-10-17 22:16:00" --style compact \
  --predicate 'process == "<procName>" OR eventMessage CONTAINS[c] "<procName>"' | tail -200
```

(See the `mac-logs` skill for predicates.) Compare file mtimes in the app's container
(`~/Library/Containers/<bundle id>`, `~/Library/Application Support/<app>`) with the crash second.

## Symbolize when you can

Most Apple frames are already symbolized. For third-party frames with only addresses:

```bash
atos -arch arm64 -o <path to binary or dSYM> -l <load address from usedImages> <frame address>
```

No dSYM means no names: say so, never invent function names. An unsymbolized stack still
shows which library each frame belongs to and whether the crash was on the main thread.

## Report

1. What crashed and what it was doing.
2. The most likely mechanism, separating what the evidence **proves** from what you **infer**.
3. Whether user data was lost and where to recover it (autosave, Versions, Trash, iCloud).
4. Whether it will recur and what would avoid or fix it (update, reinstall, reset its prefs with `macctl`, report to vendor).

**Leave the Mac as you found it.** Diagnosis reads; it does not fix or tidy. If a fix is
clear and small, offer it and do it only when asked (Summon checkpoints every session, so it can be undone).

**Exception: the user's own apps.** When the crashed program is an app in `~/Summon/Apps/<name>` (check
`summon project list`) and the request asked for a fix (Summon's "Crashed" badge does), fix the code: reproduce
with a Core test when the cause is logic, run `scripts/check.sh`, relaunch the app, and report what was wrong.

## Offer to mute this one app

End by offering, never running unprompted:

```bash
summon crash mute '<app name>'        # stop notifications for it
summon crash mute '<app name>' off    # undo
summon crash mute                     # list
```

Quote the name. Muting does not fix anything; offering a mute instead of a fix that was within reach is the wrong answer.

## If it's one of our plugins

If the crashed process is a Summon or `local.macplugins.*` app, gather `summon debug --print --since 1h`
and offer to open an issue on its dev repo with the report attached (ask first; it leaves the Mac).
