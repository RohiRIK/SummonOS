---
type: Reference
title: Configuration and state locations
description: "Where SummonOS and macctl keep configuration, state, projects and recovery data, and what uninstall touches (and never touches)."
tags: [configuration, state, paths, uninstall]
---

# Configuration and state locations

This page lists every file and folder SummonOS and macctl read or write on your Mac, so you can back up, move away from, or troubleshoot an installation without guessing. Paths are for the installed release; source checkouts read the same layout under your home.

## Summon: app, commands and shared files

| Location | Holds | Touched by uninstall |
|---|---|---|
| `~/Applications/Summon.app` | The menu bar app | Yes, when the receipt matches |
| `~/.local/bin/summon` | The `summon` CLI (symlink into the app) | Yes, when the receipt matches |
| `~/.local/bin/macctl` | The settings CLI | Yes, when the receipt matches |
| `~/Library/Application Support/Summon/install-manifest.json` | Private install receipt: paths, parents, SHA-256 fingerprints | Read and re-validated before anything is deleted |
| `SUMMON_PATH`, else `<binary>/../share/summon`, else the folder holding the binary | Shared files: themes, skills, wallpapers | No |

The installer links `summon` and copies `macctl` into `~/.local/bin`; add that folder to your shell's PATH if it is not there already.

## Summon configuration (`~/.config/summon/`)

| File or folder | Holds | Written by |
|---|---|---|
| `defaults/agent` | Default coding agent id | `summon default agent <id>` |
| `defaults/terminal` | Default terminal (`ghostty`, `kitty`, `terminal`) | `summon default terminal <name>` |
| `defaults/channel` | Update channel (`stable\|edge`), remembered between runs | `summon update --channel <channel>` |
| `agents.json` | Per-agent model and Summon skills | `summon agents set <agent> ...` |
| `tasks.json` | Recurring tasks: schedule, agent, execution mode, directory | `summon task add ...` |
| `current-theme` | Active theme slug | `summon theme set <slug>` |
| `themes/` | Installed themes (`theme.json` + wallpapers) | Installed or created themes |
| `generated/` | Theme-generated configs and editor themes, tracked for undo | Theme application |
| `hooks/` | Hook scripts for `theme-set`, `post-login`, `post-update`, `wake`, `crash` | `summon hooks list` / `hooks run` |
| `menu.jsonc` | The Summon Menu tree (searchable panel entries) | `summon menu init` |
| `projects.json` | Summon-made projects: name, kind, path, repo | `summon project new` / `register` / `import` |

`projects.json` is private to this Mac. It is not `plugins.json`, and Summon-made projects never appear in the workspace registry.

## Summon state (`~/.local/state/summon/`)

| File | Holds |
|---|---|
| `events.jsonl` | Activity log (JSON lines, oldest first): settings changes, undos, checkpoints, agent sessions, themes, crashes, Mac changes |
| `app.json` | App health written by the menu app on launch (pid, hotkeys, notification permission); read by `summon doctor` |
| `agent-updates.json` | Last agent update check (method, current and latest version), cached 24 hours |
| `crash-marker`, `crash-muted` | Crash announcement state and muted programs |
| `backups/connect/` | Backups of files `summon connect` edits directly, before it edits them |

State is not configuration: back it up separately if you care about history; uninstall preserves all of it.

## `~/Summon`: the one home for what Summon makes

| Folder | Holds |
|---|---|
| `Apps/<name>/` | Projects built from templates (`menubar`, `menubar-panel`, `launcher`, `hud`, `notch`, `app`, `widget`, `cli`, `screensaver`) |
| `Art/<job>/` | Wallpaper and icon candidates |
| `Tasks/<id>/` | One folder per recurring task, one log per run |
| `Themes` | Link to installed themes |
| `Showcase/index.html` | Gallery written by `summon showcase` |

Agents normally start in `~/Summon` when launched from `~` or `/`. Apps are never touched by cleanup; `summon clean` moves only eligible old task logs and art jobs to the Trash.

## macctl (`~/Library/Application Support/macctl/`)

| Folder | Holds |
|---|---|
| `snapshots/` | One `<id>.json` per change session; the old values a setting had before macctl wrote it |
| `journal/` | Append-only `journal/<id>.jsonl` (0600 in a 0700 directory): each change's intent and prior state, fsynced before the write |

This is local recovery history, not an indefinite backup: finished unflagged journal sessions are eligible for pruning only when older than 30 days and outside the newest 100; pending, flagged and legacy snapshots are retained. Undo cannot recreate missing wallpaper files or displays, and does not reverse restarts, logouts or app relaunches. See the [macctl settings catalog](../macctl/docs/settings.md) and [security and recovery](security-model.md).

## Source builds

| Location | Holds |
|---|---|
| `~/.summonos` | Source checkout used by `install.sh --from-source` (override with `SUMMONOS_HOME`; ref with `SUMMONOS_REF`, default `main`) |
| `~/Library/Caches/macplugins/` | Build caches, outside cloud-synced source trees |

## Files Summon edits on your behalf

`summon connect` edits per-agent configuration (for example `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.cursor/hooks.json`, `~/.gemini/config/hooks.json`) and writes a marked "This Mac" note where the target supports one. Backups go to `~/.local/state/summon/backups/connect/`; vendor CLI edits remain the vendor's responsibility.

## What uninstall never touches

`tools/uninstall.sh` removes only receipt-owned installation entries (`Summon.app`, the two commands, owned skill symlinks). It never removes `~/.config/summon`, `~/.local/state/summon`, `~/Summon`, `~/Library/Application Support/macctl`, or any project, theme, checkpoint, log or scheduled task. See [uninstall and data preservation](uninstall.md).
