# Project Context

## Overview
Summon is Rohi's agent layer for macOS: one default coding agent summoned from anywhere
(hotkey, drop-down terminal, menu bar, Summon Menu, notifications), the Mac handing it crashes and failures,
skills linked into every agent CLI, one theme across macOS, terminal, tiling, borders and agents, and a
checkpoint before every agent session. It started from research on Omarchy 4.0; it is designed as its own thing.

## Current State
- Incubating at `incubator/summon/` in `RohiRIK/macos-plugins`. Target repos: `mac-summon-dev` / `mac-summon`.
- `plugin/`: Claude Code plugin (4 skills, 7 commands, `macctl` MCP). `themes/`: 9 theme.json + wallpapers.
  `config/`: Brewfile, AeroSpace, Ghostty, borders, zsh. `design/`: brand assets + `generate.py`.
- Swift package: `SummonCore` (agents, launch plans, .ips crash parsing + watcher, menu tree, themes + compilers,
  checkpoints, debug bundle, hooks, command catalog), `summon` CLI, `SummonMenuUI` + `SummonMenu` app (menu bar panel,
  ⌃⌥Space launcher, ⌃⌥⌘A agent, crash notifications, Activity window, Settings). Builds on CI; installed and used on Rohi's Mac 2026-10-18.
- Projects: `templates/{menubar,app,cli,screensaver}` (each a buildable package with README, MIT LICENSE,
  PROJECT-CONTEXT.md, `scripts/check.sh`; CI builds them). `summon project new` copies one to `~/Summon/<name>` and
  records it in the private `~/.config/summon/projects.json`; `summon project repo` makes a private repo after a
  native dialog. Core: `Projects.swift`. Bundled into `Contents/share/summon/templates`.
- Bundle id `local.macplugins.summon`. Depends on `macctl` (`macctl/` in the workspace) for every settings change.

## Constraints
- Original design: Omarchy and other projects are research, not a spec to port (Rohi, 2026-10-18).
- Agents run with permission prompts bypassed (YOLO: `--dangerously-skip-permissions` etc.) behind a checkpoint + one-step undo (Rohi, 2026-10-17; bypass 2026-10-18).
- Third-party tools via Homebrew are allowed (AeroSpace, Ghostty, JankyBorders) (Rohi, 2026-10-17).
- Shape: Claude Code plugin + native Summon Menu app (Rohi, 2026-10-17). Name chosen by Rohi: Summon.
- Settings go through `macctl`; no passwordless sudo (Touch ID for sudo instead).
- Panel vs Settings window split from AGENTS.md applies to the Summon Menu app.
- Projects live in `~/Summon/<name>` (created on install, app launch and agent launch; agents start there). The
  project list is private to the Mac: never `plugins.json`, never `tools/mp new/promote` (Rohi, 2026-10-18).
- GitHub: only a private repo, only through `summon project repo` after the user clicks the native NSAlert (Cancel
  is the default button; no flag skips it; no GUI session = no). CI is added with the repo, not before. Public
  publishing is a separate choice through the workspace's `tools/publish-public.sh` (Rohi, 2026-10-18).

## Recent History
### 2026-10-19 — Agents settings, Hermes-style
- Studied Hermes.app's Settings (Providers/Accounts, Model from the provider's list or Custom model…, Plugins with
  Skills/Toolsets search and "N of M"). Summon's lean version: master-detail Agents tab (780×560): All Agents
  (defaults) on top, then each agent with the same four sections (Account, Model, Skills, Plugins).
- `AgentSettings.defaultSkills` (agents.json): an agent with no own list follows it; toggling back to the defaults
  clears the agent's list. `summon agents defaults`. Terminal tab removed (its picker is on All Agents).
### 2026-10-19 — Agent plugins and a shared catalog
- `AgentPlugins` (Core): list/install per agent from real output: `claude plugin list|install name@marketplace`,
  `agy plugin list|install <folder>`, `pi list|install npm:<pkg>`, OpenCode `plugin` array in `opencode.json`
  (edited with a `.summon-backup`), Codex `mcp list` (read-only). `PluginCatalog`: OpenLTM builds for claude,
  opencode, pi; `summon plugins install|fix`. Settings › Agents: Plugins + Shared plugins sections (not seen on
  screen yet: SwiftUI scroll is out of reach for automation; data verified through the CLI).
### 2026-10-19 — Problems archive; low-memory events
- `ProblemArchive` (Core, `~/.local/state/summon/problems-archived.json`): the panel shows reports ≤ 24 h old and
  not archived; Diagnose archives that program's reports; Clear archives the rest. Activity is unchanged.
- bug_type 298 is Jetsam (`CrashReport.Kind.memory`); 288 stays hang. The subject is the process with a `reason`
  (killed), not `largestProcess`: `process`/`pid` from it, `exceptionType` = plain reason (`memoryReason`).
  `isRoutine` (per-process-limit, idle-exit) → no notification. Learned from the agent's diagnosis of a real report:
  knowledgeconstructiond over its own cap, while the Mac had 44% free.
### 2026-10-19 — Agent account and models in Settings
- `AgentProbe` (Core): per CLI the login check and model list, parsers from real output: claude `auth status` (JSON),
  codex `login status` (on stderr), opencode `auth list` (stored providers), agy `models` (also the login signal),
  pi `--list-models` + `auth check --provider <model's provider | settings.json defaultProvider>`. Claude Code has no
  list: aliases opus/sonnet/haiku. `summon agents status|login`, `skills list --json` (frontmatter descriptions).
- Probes run the agent's full path with PATH = Summon's search path (no shell: the login shell lacks bun's PATH,
  the interactive one prints noise). Search order now user folders before Homebrew (two OpenCodes on this Mac).
### 2026-10-19 — Agents start through the login shell
- Ghostty/kitty run commands via `login … bash --noprofile --norc`: `#!/usr/bin/env node` agents (Pi, Codex,
  OpenCode from bun) failed (`env: node: No such file or directory`). `AgentLauncher.inLoginShell` wraps the argv
  as `$SHELL -lic 'exec "$@"' summon-agent <agent> …` (argv stays argv); Terminal.app already uses the shell.
  `ToolLocator` also searches `~/.bun/bin`. Verified from `env -i`: Pi starts and stays up in Ghostty.
### 2026-10-19 — Repo approval dialog stays open
- `summon project repo`: the NSAlert closed itself after ~2 s and `summon` exited 0 with no answer (async main runs
  main-actor work off the real main thread; a run loop stop ended it). The dialog now runs in `osascript`
  (`display dialog`, text passed as argv, Cancel default). Checked on the Mac: dialog stays up, approve made a private
  repo with CI and pushed it.
### 2026-10-19 — Tasks by conversation; Settings › Tasks view only; local CI
- `summon task new [wish]` launches the default agent with `TaskSetup.prompt`: ask what is unclear, write a complete
  unattended run prompt, `summon task add`. summon-mac skill has a "Recurring tasks" section. Launcher: Agent ›
  Schedule a Task…. Verified: Claude turned "every 6 hours, warn under 20 GB free" into a read-only task that ran.
- Settings › Tasks shows name, schedule, agent, last result only (owner: no editing there).
- Merge gate = `tools/local-ci.sh <pr>` (commit status `local / swift (macOS)`); GitHub Actions is unpaid.
### 2026-10-19 — Recurring agent tasks
- `summon task add "<prompt>" (--at HH:MM [--weekdays] | --every <n>h) [--agent] [--name]`, `list`, `remove`, `run`.
  `tasks.json`; one LaunchAgent per task (`local.macplugins.summon.task.<id>`, user's PATH captured at add) calling
  `summon task run <id>`: checkpoint, the agent's verified headless form (claude -p, codex exec, opencode run, agy -p,
  pi -p) in `~/Summon`, 30 min cap, log per run, `task.done` / `task.failed` event, notification.
- Settings › Tasks: list with Run Now / Delete, and a New Task form. Verified with Claude: direct run and a
  launchd `kickstart` both produced the answer, the event and the log; remove unloads and deletes the plist.
### 2026-10-19 — Settings as toolbar tabs; summon:// URLs fixed
- Owner's choice: PR #34's sidebar Settings becomes toolbar tabs (macOS app-settings layout), 580×460: General,
  Agents, Terminal, Notifications, Appearance. Tasks returns with item D (no empty tab).
- `summon://activity` / `summon://settings` never worked: the MenuBarExtra label is drawn as an image, so the opener
  modifier on it never ran. Openers now live in an invisible 1×1 `Window` presented at launch (`OpenerHost`).
- A stale `~/Applications/Summon.app` (older install) received every `summon://` URL and started a second Summon;
  run the installed copy (`scripts/install.sh`) so there is one app. Skill links now point at `~/Applications`.
### 2026-10-18 — Docs: original framing, features list
- README no longer pitches Summon as an Omarchy port; the seven community palettes are credited as such.
- Every command, menu entry, setting and skill is listed in the workspace's `docs/features.md`.
### 2026-10-18 — Projects: templates, ~/Summon, private list, private repos (folds in PR #34)
- Four templates (menu bar app, window app, CLI tool, screensaver), bundle ids `local.summon.<name>`, each with
  `scripts/check.sh` (build, tests, plist lint, bundle / release + `--help`), LICENSE and PROJECT-CONTEXT.md.
- `summon project new|list|path|forget|repo`; `ProjectService` copies the template (renames `Starter` and
  `<kind>-starter`, fills the date), `git init` + first commit, registers. `PrivateRepoService` asks the approver
  before writing anything, adds `.github/workflows/check.yml`, runs `gh repo create … --private`, pushes.
- `~/Work` is gone: `SummonPaths.projects` = `~/Summon`; agents launched from `~` or `/` start there.
- Make Something and `/summon:new-*` (new: New Command-Line Tool, `/summon:new-cli`) run `summon project new`
  instead of the workspace's `scratch/`. Existing `~/.config/summon/menu.jsonc` keeps the old entries until
  `summon menu init --force`.
- PR #34 (Settings window with a sidebar: General, Agents, Terminal, Notifications, Appearance, Tasks) is in the
  same PR. Its previews were never rendered; needs a look on the Mac.
- Not run on a Mac yet: the dialog, `gh repo create`, the templates' bundle scripts.
### 2026-10-18 — `summon doctor`
- `summon doctor [--json]` (SummonCore `Doctor`): pass/warn/fail with a fix for install (app, CLI on PATH, shared
  files), config (folder, default agent, agents.json, terminal, menu, themes, ~/.config git), macctl (+ its doctor),
  state folder, event log, skill links per installed agent, Claude Code plugin, app/hotkeys/notifications, crash
  report access. Exit 1 when any check fails.
- The menu app writes `~/.local/state/summon/app.json` on launch (pid, hotkeys registered, notification permission)
  because only the app knows those.
- Doctor also checks the four project templates in the shared files, `~/Summon` (projects.folder) and
  `projects.json` (projects.registry: broken file fails, missing project folders warn).
### 2026-10-18 — Per-agent model and skills
- `~/.config/summon/agents.json` (AgentSettings): per agent a model and the Summon skills it gets (default: CLI's
  model, every skill). `summon agents set <agent> --model … --skills a,b | --all-skills | --default-model`.
- Model flag only where verified: claude/codex/agy/pi `--model`; OpenCode's TUI has none (config chooses).
- Linker uses each agent's own folder (claude, codex, `.config/opencode/skills`, agy `.gemini/config/skills`, pi) and
  removes Summon links from the shared `~/.agents/skills` (it would leak skills to every agent). Codex reads
  `~/.codex/skills` (probed). OpenCode also reads `~/.claude/skills`, so it sees Claude's choice too.
### 2026-10-18 — `summon` is the router skill
- `summon` skill = router: "summon, <anything>" → summon-mac (settings, configs, installing themes), summon-art,
  mac-app, diagnose-crash-mac, mac-logs, or the agent's best other installed skill. The old Mac-customization skill
  is now `summon-mac`. Verified with agy: web app → FrontendDesign, Dock → summon-mac, wallpaper → summon-art.
- Pi added as an agent (`pi`, `pi -- <prompt>`, skills in `~/.pi/agent/skills`).
### 2026-10-18 — summon-art skill (Art know-how shipped with Summon)
- New shipped skill `plugin/skills/summon-art/`: brief → three concepts → OKLCH palette for theme.json (with a
  contrast check script) → Nano Banana via agy → review → install. `wallpapers.md` (moved from summon/Wallpapers.md)
  and `icons.md`. Named `summon-art`, not `art`: APFS is case-insensitive and `art` would replace the user's `Art` link.
- New Theme / New Wallpaper / New Icon prompts name it; `summon skills link` puts it in every agent's folder
  (verified: agy and Claude Code list it).
### 2026-10-18 — Skills linked into every agent (Omarchy's way)
- `summon skills link` (also run by install.sh and on every app launch) symlinks every shipped skill into
  `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, `~/.gemini/config/skills`; a real folder of the user's is kept.
- Antigravity's CLI reads only `~/.gemini/config/skills` (probed with agy 1.4.2; not `~/.antigravity`, `~/.gemini/skills`,
  `~/.gemini/antigravity/skills`). Verified: agy and Claude Code list all four Summon skills after linking.
- Every agent prompt ends with the skill file paths ("if your harness has no skill mechanism, read the file"); the crash
  prompt now points at the shipped copy (it named a file that never existed).
### 2026-10-18 — Activity as a simple log (user: "easier, not complicated")
- Activity window = one plain list, oldest first, opens at the newest line: `HH:mm  sentence` in monospace, only
  problems coloured, no columns or fields (full line in the tooltip and in copies). Checkpoint lines hidden (every
  agent start logs one); paths shortened to their last two parts.
- Ask bar at the bottom; selected lines go to the agent with the question. Right-click: Ask, Copy, Diagnose, Show in
  Finder, Undo This Change / Session (confirmation). Status drawer, scopes and detail views removed.
### 2026-10-18 — kitty, muted apps, art-directed wallpapers
- kitty: `TerminalApp.kitty` (`open -na kitty --args --single-instance`), `summon default terminal`, Settings "Open in"
  picker (installed terminals only), Install › kitty, `generated/kitty.conf` from every theme. Not run for real: kitty not installed.
- Settings › Notifications lists muted programs with Unmute (only when any). Verified mute → row → Unmute in the real app.
- `plugin/skills/summon/Wallpapers.md`: Art-skill direction (mood → 3 concepts, theme palette, desktop composition,
  Nano Banana via agy, review, user picks, install). agy saves into `~/.gemini/antigravity-cli/brain/…` instead of
  the asked path; the recipe recovers it. Launcher › Make Something › New Wallpaper.
### 2026-10-18 — Agent opens one Ghostty window
- `open -na Ghostty` spawned a new Ghostty process per launch (user saw two tabs). `LaunchPlan` now uses Ghostty's
  AppleScript `new window` when it is running, `open -na` only on a cold start. Verified: 1 process, +1 window.
### 2026-10-18 — Leaner panel and Settings (user request)
- Panel: no Theme list, no Recent Activity, no Diagnose Last Crash row (history → Activity window, theme → Settings).
  Recent Problems only when present, one row per program with "N times". `.ultraThinMaterial` window background (user
  asked for more translucency). Width 300. Settings footer: "Powered by caffeine and questionable choices."
- Settings: Agent, Notifications, Appearance, General only; shortcut rows and help text removed. 480×440, no scroll.
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
