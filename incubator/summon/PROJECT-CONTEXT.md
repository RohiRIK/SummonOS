# Project Context

## Overview
Summon brings the Omarchy 4.0 experience to macOS for Rohi: one default coding agent summoned from anywhere
(hotkey, drop-down terminal, menu bar, Summon Menu, notifications), the Mac handing it crashes and failures,
skills linked into every agent CLI, one theme across macOS, terminal, tiling, borders and agents, and a
checkpoint before every agent session.

## Current State
- Incubating at `incubator/summon/` in `RohiRIK/macos-plugins`. Target repos: `mac-summon-dev` / `mac-summon`.
- `plugin/`: Claude Code plugin (4 skills, 7 commands, `macctl` MCP). `themes/`: 9 theme.json + wallpapers.
  `config/`: Brewfile, AeroSpace, Ghostty, borders, zsh. `design/`: brand assets + `generate.py`.
- Swift package: `SummonCore` (agents, launch plans, .ips crash parsing + watcher, menu tree, themes + compilers,
  checkpoints, debug bundle, hooks, command catalog), `summon` CLI, `SummonMenuUI` + `SummonMenu` app (menu bar panel,
  ⌃⌥Space launcher, ⌃⌥⌘A agent, crash notifications, Settings). Written 2026-10-17, not compiled yet.
- Bundle id `local.macplugins.summon`. Depends on `macctl` (draft PR #6) for every settings change.

## Constraints
- Agents run in auto mode with checkpoint + one-step undo (Rohi, 2026-10-17).
- Third-party tools via Homebrew are allowed (AeroSpace, Ghostty, JankyBorders) (Rohi, 2026-10-17).
- Shape: Claude Code plugin + native Summon Menu app (Rohi, 2026-10-17). Name chosen by Rohi: Summon.
- Settings go through `macctl`; no passwordless sudo (Touch ID for sudo instead).
- Panel vs Settings window split from AGENTS.md applies to the Summon Menu app.

## Recent History
### 2026-10-18 — Plugin session hooks (milestone 3 of 3)
- `plugin/hooks/hooks.json` + `summon-session.sh`: SessionStart/SessionEnd call `summon event hook start|end` (payload on
  stdin; compactions skipped; silent when summon is missing). `/summon:activity` command summarizes status and events.

### 2026-10-18 — Activity window (milestone 2 of 3)
- `ActivityModel` + `ActivityView`: a `Window` scene ("Summon Activity") with a day-grouped timeline, filter and search,
  a status overview when nothing is selected, per-event detail (old → new values, Undo This Change, Undo Session,
  Diagnose/Mute for crashes) and a run bar (⌘↩ asks the default agent through `summon agent prompt`).
- Panel: "Activity…" row, the 3 newest events, "running since" in the header. `summon://activity` opens the window.
- The window switches the app to a regular activation policy while open (Dock icon, ⌘Tab), back to accessory on close.
- Not yet run on a Mac: window opening from the menu bar label, activation policy switch, 3 s refresh.

### 2026-10-18 — Activity: event log, timeline, status (milestone 1 of 3)
- `EventLog` (`~/.local/state/summon/events.jsonl`), `ActivityFeed` (merges the log, macctl snapshot files,
  checkpoints and crashes, sorted by date), `StatusProbe`; CLI `summon status`, `summon events`, `summon event add`.
- `summon agent`, `theme set` and `undo-session` record events. Plan: `/mnt/project-files/plans/2026-10-18-summon-activity.md`
  (next: Activity window in the menu app, then plugin session hooks).

### 2026-10-18 — Wallpaper through macctl
- `summon theme set` sets the wallpaper with `macctl set desktop.wallpaper` when macctl is installed (undoable), else NSWorkspace.

### 2026-10-18 — Match macctl's real keys and snapshots
- Profile, menu and `theme set` use `appearance.dark-mode` (true/false); macctl has no wallpaper or screensaver keys.
- Checkpoints record macctl's newest snapshot id as a marker; undo reverts every macctl snapshot after it, newest first.

### 2026-10-18 — Swift package merged (PR #13)
- CLI, menu app, swift-testing tests; review fixes (cwd, checkpoint undo, runner, hotkey, guards).
- Green on macOS CI (Xcode 26.6, Swift 6.3): builds, 38 tests pass. Not yet run by hand on a Mac (bundle, hotkeys, notifications).

### 2026-10-17 — Design, themes, plugin, configs
- Logo (summoning circle around `›_`), app icon, menu bar template icon, wordmarks, banner.
- Summon Night / Dawn themes + 7 Omarchy palette ports, 12 wallpapers at 5120×2880.
- Claude Code plugin skills and commands; AeroSpace/Ghostty/borders/zsh configs; Brewfile.
