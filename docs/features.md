---
type: Reference
title: Features
description: "Every user-visible feature of Summon, macctl, the SummonOS apps and the workspace tools, in one list."
tags: [features, summon, macctl]
---

# Features

Everything each SummonOS project can do today, in one place. "Planned" marks what is designed
but not built. Keep this page current: a PR that adds or removes a user-visible feature updates it
([`AGENTS.md`](../AGENTS.md#how-we-work), step 7).

- [Summon](#summon): one coding agent you summon from anywhere on the Mac
- [macctl](#macctl): read, set, diff, apply and undo macOS settings
- [mac-network](#mac-network), [mac-calendar](#mac-calendar), [mac-breathe](#mac-breathe) and [end-of-day](#end-of-day): apps built with SummonOS
- [The workspace](#the-workspace): tools, skills and templates for building more apps

## Summon

Code: [`incubator/summon/`](../incubator/summon). Overview: [its README](../incubator/summon/README.md).

### Summon the agent

- **Eight agents:** Claude Code, Codex, OpenCode, GitHub Copilot, Cursor CLI, Antigravity (`agy`), Pi
  and Grok. One is the default (`summon default agent`); `summon agents` shows which are installed and
  how to install the rest.
- **From anywhere:** ⌃⌥⌘A opens the agent in a new terminal window, the drop-down terminal (⌃⌥⌘\`, then
  `a`) runs it inline, and `summon agent prompt "<task>"` starts it straight into a task.
- **Terminal of your choice:** Ghostty, kitty or Terminal (`summon default terminal`). Ghostty reuses
  its running process and opens one window.
- **Per-agent settings:** a model and the set of Summon skills for each agent
  (`summon agents set`, saved in `~/.config/summon/agents.json`).
- **Skills in every agent:** `summon skills link` links Summon's skills into each agent's own skills
  folder and preserves foreign folders and symlinks. Install and every app launch run it.
- **Starts in `~/Summon`:** an agent launched from `~` or `/` starts in the projects folder.

### Safety: checkpoints and undo

- **Execution policy:** Settings › General › Agent execution or `summon default execution normal|unattended`.
  New installs use the agent's own controls; existing configured installations retain unattended execution.
  The [security model](security-model.md) explains the authority and recovery boundaries.

- **A checkpoint before every agent session:** a `macctl` snapshot marker plus a git commit of
  `~/.config` when it is already a repository (`summon checkpoint create`). Capture failures remain visible;
  scheduled work stops before launching its agent if capture reports a failure.
- **Undo:** `summon undo-session` (or `summon checkpoint undo [id]`) restores successfully captured config files
  and supported macctl settings changed since. New files and external actions are excluded. `--dry-run` shows
  the plan first. `summon checkpoint list` includes capture problems.

### The Mac calls the agent

- **Crash watcher:** the menu app notifies you about new crash, hang and panic reports. The notification
  hands the report to the agent with the `diagnose-crash-mac` skill.
- **Crash commands:** `summon crash list`, `crash show <file.ips>` (parsed facts), `crash diagnose
  --latest`, `crash mute <program>` (and `off`), with muted programs managed in Settings.
- **Debug bundle:** `summon debug [--print] [--save] [--since 1h]` collects the macOS version, hardware,
  recent errors, reports and packages, with best-effort redaction and private saved files. Review before sharing.

### Summon panel and Summon Menu (⌃⌥Space)

The menu bar panel (⌃⌥Space) with the Summon Menu opens under the Summon icon from a left click, ⌃⌥Space, `summon panel` or
`open -g summon://panel` (`summon panel --close` closes it). It takes typing without taking focus from the app
you're in, and Esc returns you there. Right-click the icon for Settings… and Quit.

At the top of the panel is the Summon Menu: a searchable, keyboard-first menu tree defined in
`~/.config/summon/menu.jsonc` (`summon menu init`, `menu list`, `menu summon [id]`, which opens the panel at that
entry). There's no separate launcher window. Entries can be hidden, checked or disabled by shell guards. Default
sections:

| Section | Entries |
|---|---|
| Agent | Ask Agent, Diagnose Last Crash, Save Debug Bundle, Undo Last Agent Session, Default Agent |
| Style | Theme, Dark Mode, Light Mode, Start Screensaver |
| Setup | Show Profile Drift, Check Permissions, Edit This Menu, Open Hooks Folder, System Settings |
| Trigger | Screenshot Area, Screenshot to Desktop, Stay Awake for 1 Hour, Lock Screen |
| Make Something | New Menu Bar App, New App, New Command-Line Tool, New Screensaver, New Theme, New Wallpaper, New Icon |
| Install | Ghostty, kitty, AeroSpace Tiling, Window Borders (each only when missing) |
| Update | Update Homebrew Apps, Check for macOS Updates |
| System | Sleep, Restart…, Log Out…, Shut Down… |

### Menu bar app

- **Panel:** Ask Agent, Open Summon Menu, Activity…, Recent Problems (only when there are some, one row
  per program with a count and Diagnose…; a report leaves after 24 hours, once diagnosed, or with Clear), then Settings… (⌘,) and Quit (⌘Q).
- **Activity window:** a plain, oldest-first log of settings changes, undos, agent sessions, themes and
  crashes and recurring tasks, opened at the newest line (also `summon://activity`). Select lines and ask the agent about them
  from the bar at the bottom. Right-click a line to Ask, Copy, Diagnose, Show in Finder, or Undo This
  Change / Session.
- **Settings window** (⌘, or `summon://settings`), one toolbar tab per part:
  - General: Open at Login.
  - Agents: a list of agents (status dot, Default) with **All Agents** on top: the default agent, where agents
    open (Ghostty, kitty or Terminal), the skills every agent gets, and shared plugins (OpenLTM: Install in All).
    Each agent's page has the same sections: Account (Connected, or Log In…), Model (from that agent's real model
    list, or Custom…), Skills (same as All Agents, or Custom), Plugins (installed, recommended, Add).
  - Notifications: crash and hang alerts, muted programs with Unmute.
  - Appearance: the theme.
  - Tasks: each recurring task with its schedule, agent and last result (view only).

### Activity and status from the command line

- `summon status`: agent, macctl, last change, last checkpoint and recent problems at a glance.
- `summon events [--kind settings|agent|checkpoint|theme|problem] [--limit N]`: the same timeline as the
  Activity window. `summon event add` and `event hook start|end` let tools write to it. The Claude Code
  plugin's session hooks use them.
- `summon doctor`: checks Summon's own install (app, CLI, config, macctl, event log, hotkeys,
  permissions, skill links) with a fix for each failure.

### Themes and look

- **Nine themes:** Summon Night (default) and Summon Dawn, plus seven community palettes (Tokyo Night,
  Catppuccin, Gruvbox, Nord, Rosé Pine Dawn, Kanagawa, Everforest), each with 5K wallpapers.
- **One command restyles everything:** `summon theme set <slug>` sets macOS dark or light mode, the
  wallpaper (through `macctl`, so it can be undone), Ghostty, kitty, window borders and Claude Code.
  There is also `theme list` and `theme current`.
- **Custom icons** on any file, folder or app: `summon icon set <image> <path>`, `icon reset`.
- **Hooks:** scripts in `~/.config/summon/hooks/<event>.d/` for `theme-set`, `post-login`,
  `post-update`, `wake` and `crash` (`summon hooks list`, `hooks run`).
- **Desktop layer (optional, Homebrew):** AeroSpace tiling with an ⌥ keymap (⌥1…9 workspaces,
  ⌥H/J/K/L focus, ⌥⇧H/J/K/L move, ⌥Return Ghostty), JankyBorders, Ghostty with a drop-down quick
  terminal, a Nerd Font, and shell aliases `a` / `ap` for the agent ([`config/`](../incubator/summon/config)).

### Make things: projects from templates

- `summon project new <name> --kind menubar|app|cli|screensaver` copies a template to `~/Summon/<name>`,
  runs `git init` with a first commit, and records it in a private list (`~/.config/summon/projects.json`).
  Also `project list`, `project path`, `project forget`.
- **Templates:** menu bar app, window app, CLI tool, screensaver. Each builds on its own and has a tested
  Core, README, MIT LICENSE, `PROJECT-CONTEXT.md` and `scripts/check.sh`
  ([`templates/`](../incubator/summon/templates)).
- **GitHub only when you say so:** `summon project repo <name>` creates a private repo with CI only after
  you click Create in a native dialog. Cancel is the default button, and no flag skips the dialog.
- Every new app gets a **private GitHub repo** right away (screenshots, CI, first push), unless Settings › General
  › "Create a private GitHub repo for every new app" is off (`summon default repos ask`): then Summon's dialog asks.
  Never public.

### Claude Code plugin

[`plugin/`](../incubator/summon/plugin), loaded with `claude --plugin-dir incubator/summon/plugin`.

| Skill | Use |
|---|---|
| `summon` | Entry point: routes "summon, …" to the right skill |
| `summon-mac` | Settings, configs, themes, tiling, terminal, keybindings, hooks, apps to install |
| `summon-art` | Themes, wallpapers and icons: concept, palette with a contrast check, images through Nano Banana, review |
| `mac-app` | Build a menu bar app, window app, CLI tool, screensaver or icon from a Summon template |
| `diagnose-crash-mac` | Why an app crashed, hung or was killed, from its diagnostic report |
| `mac-logs` | Read the unified log, app and launchd logs, install logs |

Commands: `/summon:setup`, `/summon:fix`, `/summon:theme`, `/summon:icon`, `/summon:new-menubar`,
`/summon:new-app`, `/summon:new-cli`, `/summon:new-screensaver`, `/summon:activity`.

Every `summon` command, with arguments and examples: `summon commands --json`.

### ~/Summon: one home

- Everything Summon and its agents make lives in `~/Summon`: `Apps/<name>` (projects from the templates), `Art/<job>`
  (wallpaper and icon candidates), `Tasks/<id>` (a log per task run), `Themes` (a link to the installed themes).
  Agents start there. `~/Summon/.gitignore` keeps the generated parts out of git. `summon home` sets it up and moves
  older Summon files in.
- Kept tidy once a day (or `summon clean --apply`, Settings › General › Clean Now…): old task logs, art jobs untouched
  30 days and Antigravity originals after 14 days go to the Trash; apps are never touched; unfinished or broken
  themes are reported. `summon clean` previews.

### Screenshots and the showcase

- `summon project shots <name>`: light and dark pictures in the app's `docs/screenshots/`, a Screenshots section in its
  README, committed; also run by `summon project repo` before the first push. Menu bar apps draw their own panel
  (`--screenshot`); window apps are captured live. CLI tools get their `--help` in the README.
- `summon showcase`: `~/Summon/Showcase/index.html`, every app with its pictures, kind and summary.

### Recurring agent tasks

- Describe it, the agent sets it up: `summon task new "every weekday at 9, check brew updates"` (or Summon Menu ›
  Agent › Schedule a Task…, or "summon, every morning…" in any agent chat). The agent asks what is unclear, writes
  a complete run prompt (it runs unattended), and adds the task.
- Directly: `summon task add "<prompt>" --at 09:00 [--weekdays]` or `--every 2h`, optionally `--agent <id>` and
  `--name`, `--execution normal|unattended` and `--directory <path>`; `summon task list`, `summon task run <id>`,
  `summon task remove <id>`. New tasks retain the selected agent, execution mode and directory.
- Settings › Tasks shows each task (schedule, agent, last result), view only.
- Each task is a LaunchAgent that runs the agent's print mode in the saved directory (default `~/Summon`),
  after a checkpoint, with a 30-minute deadline. Overlapping runs are refused; failures return nonzero and
  appear in Activity. Bounded private logs live in `~/Summon/Tasks/<id>/`. Deadline/cancellation clean up the
  invocation's process group; deliberately detached processes and completed external effects are excluded.

### Planned

- A quick task desk: a small floating panel to hand the agent a request from anywhere (parked by the owner).

Changes, newest first: [`incubator/summon/CHANGELOG.md`](../incubator/summon/CHANGELOG.md).

## macctl

Code: [`macctl/`](../macctl). Overview: [its README](../macctl/README.md).

- **Typed catalog:** every setting has an id, a type, a risk tier, the permissions it needs and its side
  effects. Use `list [--domain]`, `describe <id>` and `get <id>...`.
- **Change safely:** `set <id> <value>` and `apply <profile.json> [--only <domain>]`, with `--dry-run`, and
  `diff <profile>` to preview. `admin` and `destructive` settings need `--yes`.
- **Snapshots and undo:** every write saves the old values first. `snapshot list`, `snapshot show <id>`,
  and `undo [<id>]`. Each key's prior state (absent, explicit with its exact plist type, or inherited; managed keys are refused)
  is recorded before the write, so undo deletes what was unset or inherited and writes back exact typed values.
  Transactions serialize across cooperating processes.
- **Crash recovery:** every change is journaled step by step (`journal/<id>.jsonl`, 0600, synced per line) under
  a write-once header. After a crash, `set`, `apply` and `undo` stop with `recovery_pending` until
  `macctl recover` rolls the unfinished session back to its prior state; `recover --abandon <id>` sets an
  unreadable journal aside. A key changed by hand since macctl wrote it is left as it is and flagged, and undo
  reports `partial_restore`; `undo <id> --force` (explicit user only, never passed by Summon) overwrites it.
  Wallpaper recovery retains distinct per-display images; legacy snapshots remain readable.
- **Built for agents:** `--json` (automatic in a pipe) prints one object per run with stable error codes
  and exit codes. `doctor` checks permissions without triggering a prompt and links to the right System
  Settings pane.
- **Profiles:** JSON files of desired values. `apply` is idempotent and restarts Dock, Finder or
  SystemUIServer once at the end.

Settings (19, full table in [`macctl/docs/settings.md`](../macctl/docs/settings.md)):

| Domain | Settings |
|---|---|
| Dock | autohide, tile size, show recents, orientation, minimize effect, autohide delay |
| Finder | show extensions, path bar, status bar, default view, hidden files |
| Keyboard | key repeat, initial key repeat, press and hold |
| Screenshots | location, format, disable shadow |
| Appearance | dark mode |
| Desktop | wallpaper (every screen) |

Agents use it through the workspace skill `MacSetup`.

## mac-network

Menu bar app for Wi-Fi and IP settings ([public repo](https://github.com/RohiRIK/mac-network); port of
Rohi's own Linux widget `rohi.network`).

- Wi-Fi on/off, network list and connect (CoreWLAN; needs Location permission to see names).
- Live details: IP, link speed, band, ping, packet loss, rate. Public IPv4 on click.
- IP settings per network service: DHCP or Manual, "Use current IP", Save (an admin prompt).
- Keys: s, r, w, Esc.

## mac-calendar

Menu bar calendar ([public repo](https://github.com/RohiRIK/mac-calendar)).

- Month grid and week view, today marked, Sunday or Monday start.
- Events and reminders from Calendar (EventKit): dots on days, a day list, quick add, complete a reminder.
- Hebrew dates and holidays.
- Hotkey ⌥⌘P. Settings: calendars, reminders, Hebrew, shortcut, Open at Login.

## mac-breathe

Breathing guide in the menu bar and a full window ([public repo](https://github.com/RohiRIK/mac-breathe),
downloads on its Releases page).

- A breathing orb that grows on the in-breath and shrinks on the out-breath; menu bar panel or full-screen focus window.
- 18 techniques grouped by goal (calm, sleep, focus, balance, energy) plus a custom rhythm; a timer per technique.
- Sounds per breath, a start and end bell, optional background; trackpad taps and spoken cues.
- Streak, reminders with quiet hours; `Space` starts and stops, ⌥⌘B from any app.

## end-of-day

Closes your work apps when the workday ends ([repo](https://github.com/RohiRIK/end-of-day)); a Summon project made
with `summon project new`.

- Daily schedule with workday presets and wake catch-up; a 30-second countdown with Close Now, Snooze and Cancel.
- A catalog of 35+ work apps with a shutdown priority each; soft (countdown) or hard (force quit) mode.
- Streak, 7-day chart and run history; follows the current Summon theme live.

## The workspace

What this repo gives you for building more apps ([`README.md`](../README.md), [`docs/tools.md`](tools.md)).

| Tool | Does |
|---|---|
| `tools/okf-index.py` | Checks `docs/` is an Open Knowledge Format bundle and writes its `index.md` files |
| `install.sh` | One-line SummonOS install (Summon + macctl) from source; [`docs/install-ai.md`](install-ai.md) is the same for agents |
| `tools/mp` | Plugin registry: `new`, `promote`, `clone`, `list`, `status`, `index`, `adopt` |
| `tools/publish-public.sh` | Clean snapshot of a dev repo to its public repo; refuses on private values |
| `tools/release.sh` | Zipped `.app` on the public repo's Releases |
| `tools/render-previews.sh`, `tools/xcode-mcp.ts` | SwiftUI previews to PNG through the Xcode MCP bridge |
| `tools/check-workspace.sh` | Hygiene gate: package locations, file sizes, registry/docs indexes, design skills |
| `tools/check-skills.py` | Validates six design skills and optionally typechecks their Swift examples targeting macOS 15 |
| `tools/install-skills.sh` | Links the workspace skills into `~/.claude/skills` |
| `tools/readme-art.py`, `tools/record-demos.sh` | README art and recorded terminal demos |

| Skill | Use |
|---|---|
| `MacAppArchitecture` | App shape, layers, state, concurrency, backend calls, storage, system tools |
| `MacUX` | Views, panels, windows, menu bar items, activity feeds, HIG, polish review |
| `LiquidGlass` | Modern native macOS views, with macOS 26 glass and macOS 15 material fallback |
| `MacAqua`, `MacClassic`, `MacLinen`, `MacNeXT`, `MacYosemite` | Explicitly requested historical styles, implemented with working native controls |
| `MacAppBuild` | Scaffold, build, previews, verify, release |
| `MacSetup` | Configure a Mac with `macctl` |
| `PortLinuxWidget` | Port a Linux widget or script to a native Mac app |
| `swiftui-expert-skill`, `swift-concurrency-pro` | Vendored (MIT): SwiftUI and Swift concurrency depth |

CI ([`.github/workflows/swift.yml`](../.github/workflows/swift.yml)) builds and tests every Swift package
on macOS on every push, including Summon's templates and `examples/menubar-starter`.
It also validates design skill structure, typechecks their Swift examples, and runs tooling regressions.
