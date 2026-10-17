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
### 2026-10-17 — Swift package (draft PR)
- CLI, menu app, swift-testing tests; review fixes (cwd, checkpoint undo, runner, hotkey, guards). Needs a Mac/CI build.

### 2026-10-17 — Design, themes, plugin, configs
- Logo (summoning circle around `›_`), app icon, menu bar template icon, wordmarks, banner.
- Summon Night / Dawn themes + 7 Omarchy palette ports, 12 wallpapers at 5120×2880.
- Claude Code plugin skills and commands; AeroSpace/Ghostty/borders/zsh configs; Brewfile.
