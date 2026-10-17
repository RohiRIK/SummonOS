---
name: mac-logs
description: >
  Read macOS logs to find out what went wrong: the unified log (`log show` / `log stream`),
  app and launchd job logs, install and update logs. Use when asked to check logs, debug why
  something does not work, why a service keeps restarting, why Wi-Fi/Bluetooth/sleep misbehaves,
  or to look around the time of a crash. Triggers: logs, Console, log show, log stream, launchd,
  "check the logs", "why does X fail", error messages, debug.
---

# Reading logs on macOS

The unified log holds almost everything, and it is enormous. Always box it in time and filter
it; never dump it whole into context.

## The unified log

```bash
# Last 30 minutes, errors and faults only, compact one line per entry
log show --last 30m --style compact --predicate 'messageType == error OR messageType == fault' | tail -300

# One app or daemon
log show --last 1h --style compact --predicate 'process == "Finder"'

# A subsystem (bundle-id style), e.g. our own apps
log show --last 1h --style compact --predicate 'subsystem BEGINSWITH "local.macplugins"'

# Text search, case-insensitive
log show --last 2h --style compact --predicate 'eventMessage CONTAINS[c] "denied"'

# A window around an event
log show --start "2026-10-17 22:10:00" --end "2026-10-17 22:20:00" --style compact --predicate '…'

# Live, while the user reproduces it, for 60 seconds (macOS has no `timeout`; never leave a stream running)
log stream --style compact --level debug --predicate 'process == "<name>"' & pid=$!; sleep 60; kill $pid
```

Predicate fields: `process`, `processImagePath`, `subsystem`, `category`, `sender`, `messageType`
(`default`, `info`, `debug`, `error`, `fault`), `eventMessage`. Combine with `AND` / `OR`, `CONTAINS[c]`,
`BEGINSWITH`, `==`. `--info` and `--debug` include lower levels in `show`.

Private data shows as `<private>`; that is by design. Do not try to turn it off.

## Where the common subsystems log

| Area | Predicate |
|---|---|
| Wi-Fi | `subsystem == "com.apple.wifi"` or `process == "airportd"` |
| Bluetooth | `subsystem == "com.apple.bluetooth"` |
| Sleep / wake | `pmset -g log \| tail -100` (better than the unified log) |
| TCC / permissions | `subsystem == "com.apple.TCC"` |
| Gatekeeper / signing | `process == "syspolicyd" OR process == "amfid"` |
| Launch agents/daemons | `process == "launchd"` plus `launchctl print gui/$(id -u)/<label>` |
| Software Update | `/var/log/install.log` |
| Homebrew | `brew doctor`, `brew config`; build logs in `~/Library/Logs/Homebrew/<formula>/` |

## A service that keeps failing

```bash
launchctl list | awk '$2 != 0 && $2 != "-"'           # jobs whose last exit was non-zero
launchctl print gui/$(id -u)/<label>                    # state, last exit reason, program, log paths
```

Its `StandardOutPath` / `StandardErrorPath` (from the plist in `~/Library/LaunchAgents`) often has the real error.

## Files apps write themselves

`~/Library/Logs/<App>/`, `~/Library/Application Support/<App>/logs/`, `~/Library/Containers/<bundle id>/Data/Library/Logs/`.
Summon's own: `~/Library/Logs/Summon/` and subsystem `local.macplugins.summon`.

## A full bundle

`summon debug --print --since 1h` gathers OS version, hardware, errors and faults from the last hour,
recent diagnostic reports, Homebrew packages, and `macctl doctor`. Read that first when the problem is vague.

## Report

Quote the few lines that matter (with timestamps), say what they mean, and separate what the log
shows from what you infer. If the log shows nothing relevant, say so and suggest what to reproduce
while `log stream` is running.
