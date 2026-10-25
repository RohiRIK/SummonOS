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
- **Session brief:** every task Summon hands an agent (menu, crash, Fix with AI, Activity, scheduled task) ends
  with a `## Summon session` block: the working folder, the checkpoint id and its undo command, whether tool calls
  are approved for the agent or prompted, the skill files, and for scheduled runs that nobody is watching.
- **Terminal of your choice:** Ghostty, kitty or Terminal (`summon default terminal`). Ghostty reuses
  its running process and opens one window.
- **Per-agent settings:** a model and the set of Summon skills for each agent
  (`summon agents set`, saved in `~/.config/summon/agents.json`).
- **Skills in every agent:** `summon skills link` links Summon's skills into each agent's own skills
  folder and preserves foreign folders and symlinks. Install and every app launch run it.
- **Starts in `~/Summon`:** an agent launched from `~` or `/` starts in the projects folder.

### Summon with what is on screen

The agent hotkey (⌃⌥⌘A) and the panel's Ask Agent start the agent with what you were looking at as its first
message, so "fix this" or "explain this" works on whatever is on screen. It includes:
- the frontmost app and window title
- the selected text, cut at 2,000 characters
- the front tab's title and URL, in Safari, Chrome, Arc, Edge, Brave and Helium
- the files selected in Finder

The message ends by telling the agent to wait for your question. Summon reads this in the moment you press the
hotkey, while your app is still in front.

Selected text and window title use Accessibility only when Summon already has it, and never ask for it. The browser
and Finder fields use AppleScript, so macOS asks once for Automation permission per app. If you say no, that field
is just left out. Every field is on by default; Settings › Agents (or `summon context hide selected-text|browser-page|finder-selection|window-title`)
turns each one off. Crash diagnosis, Activity and tasks keep their own prompts. Verified on a Mac (macOS 27.0.1,
2026-10-25): with text selected in Helium, the agent's first message had the app, window, page and selection.

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
- **Any agent's session can be undone, not only the ones Summon starts:** before an agent's first real
  `settings_set` through `summon mcp`, Summon takes a checkpoint labelled "<Agent> via MCP", such as "Codex via MCP".
  It logs the session under the agent's name from MCP `clientInfo`. The tool reply ends with the one command that
  undoes the whole session, and Activity shows it as that agent's session with **Undo This Session…**.
- **Panel:** after an agent session from the last 12 hours that changed settings, the panel shows one row, "Undo
  <Agent> Session (N changes)…". Choosing it asks first, then runs `summon checkpoint undo`. The row disappears
  when there is nothing to undo.

### The Mac calls the agent

- **Crash watcher:** the menu app announces new crash, hang and panic reports, as a Summon alert (default)
  or a macOS banner (Settings › Notifications), never both. The alert never takes the keyboard from the app you
  are typing in; a burst shows one alert ("N more"), banners group per program. Diagnose with AI hands the report
  to the agent with the `diagnose-crash-mac` skill.
- **Task results:** each scheduled run ends with a "Task done" or "Task failed" notification from Summon, with
  Show Log and Ask Agent (a plain banner when the app is not running).
- **Crash commands:** `summon crash list`, `crash show <file.ips>` (parsed facts), `crash diagnose
  --latest`, `crash mute <program>` (and `off`), with muted programs managed in Settings.
- **Debug bundle:** `summon debug [--print] [--save] [--since 1h]` collects the macOS version, hardware,
  recent errors, reports and packages, with best-effort redaction and private saved files. Review before sharing.

### Summon panel and Summon Menu (⌃⌥Space)

The menu bar panel (⌃⌥Space) with the Summon Menu opens under the Summon icon from a left click, ⌃⌥Space, `summon panel` or
`open -g summon://panel` (`summon panel --close` closes it). It takes typing without taking focus from the app
you're in, and Esc returns you there. Right-click the icon for Settings… and Quit. Pressing ⌘↵ anywhere in the
panel immediately launches the default agent in your preferred terminal in `~/Summon`.
While an agent runs, its elapsed time (`mm:ss`) shows next to the Summon icon even with the panel closed (Settings ›
General › Menu Bar turns it off), and VoiceOver reads the agent and how long it has run on the icon. Opening the
panel from ⌃⌥Space or a URL is announced to VoiceOver, since a panel that doesn't activate Summon doesn't move the
VoiceOver cursor.

At the top of the panel is the Summon Menu: a searchable, keyboard-first menu tree defined in
`~/.config/summon/menu.jsonc` (`summon menu init`, `menu list`, `menu summon [id]`, which opens the panel at that
entry). There's no separate launcher window. Entries can be hidden, checked or disabled by shell guards.
Apps built through Summon (`~/.config/summon/projects.json`) are automatically listed under a "My Apps" menu item
in the menu tree, allowing you to click or drill down into your apps and launch their built `.app` bundle or open
their project folder. Default
sections:

| Section | Entries |
|---|---|
| Agent | Ask Agent, Diagnose Last Crash, Save Debug Bundle, Undo Last Agent Session, Default Agent |
| My Apps | Your built apps (opens the built .app or reveals the project folder) |
| Style | Theme, Dark Mode, Light Mode, Start Screensaver |
| Setup | Show Profile Drift, Check Permissions, Edit This Menu, Open Hooks Folder, System Settings |
| Trigger | Screenshot Area, Screenshot to Desktop, Stay Awake for 1 Hour, Lock Screen |
| Make Something | New Menu Bar App, New App, New Command-Line Tool, New Screensaver, New Theme, New Wallpaper, New Icon |
| Install | Ghostty, kitty, AeroSpace Tiling, Window Borders (each only when missing) |
| Update | Update Homebrew Apps, Check for macOS Updates |
| System | Sleep, Restart…, Log Out…, Shut Down… |

### Menu bar app

- **Panel:** **Needs attention** at the top, only when something is wrong: one row per program that crashed
  (with a count; Diagnose… hands the newest report to the agent and the program leaves the panel; a report also
  leaves after 24 hours) and "N setup problems · Fix…" (Summon's own `summon doctor`, checked at launch and every 10
  minutes). Then the Summon Menu, Ask Agent, Activity…, the undo row when there is something to undo, Settings… (⌘,)
  and Quit (⌘Q). With no default agent, the header offers "Choose an agent" (the installed ones); with exactly one
  installed, it is chosen automatically. The menu bar icon turns orange while Needs attention has something.
- **Undo confirmation:** "Restore N Changes" names what it does; Cancel is the default button.
- **Activity window:** a plain, oldest-first log of settings changes, undos, agent sessions, themes and
  crashes and recurring tasks, opened at the newest line (also `summon://activity`). Select lines and ask the agent about them
  from the bar at the bottom. Right-click a line to Ask, Copy, Diagnose, Show in Finder, or Undo This
  Change / Session.
- **Settings window** (⌘, or `summon://settings[/<section>]`; one window, the page name is its title, no header
  blocks or explanatory text), one sidebar entry per part:
  - General: Permissions (Accessibility: On, or **Allow…**, which asks macOS to add Summon to Privacy & Security ›
    Accessibility and opens that page, so only the switch is left; the row re-checks every 2 seconds and says to
    turn the switch off and on when an older build's entry is in the way), Open at Login.
  - Agents: a list of agents (status dot, Default) with **All Agents** on top: the default agent, where agents
    open (Ghostty, kitty or Terminal), the skills every agent gets, what agents see about this Mac (computer name,
    window title, running apps, file paths: all on, each can be turned off), and shared plugins (OpenLTM: Install in All).
    Each agent's page has the same sections: Account (Connected, or Log In…), Model (from that agent's real model
    list, or Custom…), Skills (same as All Agents, or Custom), Plugins (installed, recommended, Add).
  - My Apps: apps and menu bar widgets built in `~/Summon/Apps`.
  - Terminal: the default terminal, launch behavior and window styling.
  - Notifications: crash and hang alerts (Summon alert or macOS banner), task results, sound, muted programs with Unmute.
  - Appearance: the theme.
  - Tasks: each recurring task with its schedule, agent and last result (view only).

### Activity and status from the command line

- `summon status`: agent, macctl, last change, last checkpoint and recent problems at a glance.
- `summon version` (or `--version`): prints the SummonOS version (`summon 0.1.1`); `summon doctor` shows it on its
  first line and in `--json`. One version for `summon`, Summon.app and `macctl`, kept in the root `VERSION` file.
- `summon context [--json] [--only a,b]`: this Mac for agents in one read-only snapshot (about 60 ms): model,
  chip, RAM, macOS, power and thermal state, free space per volume, network and VPN, displays, frontmost app and
  window, running apps, appearance, what the asking process may do (Accessibility, Screen Recording, Full Disk
  Access), installed agents and crashes in the last day. `summon context hide|show <field>` (or Settings › Agents)
  turns off the computer name, window title, running apps or file paths.
- `summon events [--kind settings|agent|checkpoint|theme|problem|mac] [--limit N] [--follow]`: the same timeline as
  the Activity window; `--follow` keeps printing new lines, so an agent can watch the Mac.
- **Live Mac events:** while Summon.app runs, it compares a `summon context` snapshot every 30 seconds and logs
  what changed as `mac.*` events in the Activity window. That covers: network offline or back online, VPN on or
  off, low disk space (under 20 GB) and recovered, battery low (20%) or very low (10%), the Mac running hot or
  cooling down, and displays connected or disconnected. Only crossings are logged, never the same state every
  minute. Agents read them with the MCP tool `mac_events` (11 tools now) or `summon events --kind mac --follow`. `summon event add` and `event hook start|end` let tools write to it. The Claude Code
  plugin's session hooks use them.
- **Fix with AI** (`summon fix`) hands the agent only crashes from the last 24 hours that no agent has seen yet,
  the same ones the panel shows, so pressing it again never repeats the same reports.
- `summon doctor`: checks Summon's own install (app, CLI, config, macctl, event log, hotkeys,
  permissions, skill links) with a fix for each failure.
- `summon update [--channel stable|edge] [--check] [--yes]`: updates Summon and macctl from GitHub. `stable` is the
  newest release tag; `edge` is a rolling prerelease rebuilt from every green `main` (`summon --version` then reads
  `0.1.0-edge.<sha>`). It downloads the zip and `SHA256SUMS`, refuses on a mismatch, installs with the release's own
  staged installer (rollback on failure) and runs `summon doctor`. `--check` only reports. A `--channel` is
  remembered in `~/.config/summon/defaults/channel`.

### Themes and look

- **Nine themes:** Summon Night (default) and Summon Dawn, plus seven community palettes (Tokyo Night,
  Catppuccin, Gruvbox, Nord, Rosé Pine Dawn, Kanagawa, Everforest), each with 5K wallpapers.
- **One command restyles everything:** `summon theme set <slug>` sets macOS dark or light mode, the wallpaper
  and the accent color (all through `macctl`, so they can be undone). It also restyles Ghostty, kitty, window
  borders and Claude Code, VS Code and Cursor through a "Summon" color theme (choose it once), and Neovim
  (`:colorscheme summon`, written when `nvim` is installed). It takes one checkpoint first and ends with
  `summon checkpoint undo <id>`, which undoes the whole look, including removing the files the theme created
  (generated configs, the editor themes). A folder you have added your own files to stays. The panel offers "Undo Theme <name> (N changes)…".
  There is also `theme list` and `theme current`. Settings › Appearance provides full 16:9 wallpaper previews, color swatches, one-click Apply, and an Undo button to revert to the previous theme.
- **Default terminal with auto-installer:** Settings › Terminal lets you select Ghostty, kitty, or Apple Terminal. If Ghostty or kitty is not installed, install it directly with one click via Homebrew.
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

### Every agent: the MCP server

`summon mcp` is an MCP server on stdio, so any MCP client (Claude Code, Codex, Gemini CLI, Cursor, opencode,
Raycast) can use this Mac. It is native Swift with no dependencies, and it serves 11 tools:

| Tool | Does |
|---|---|
| `mac_context` | The `summon context` snapshot (all sections or some) |
| `settings_list`, `settings_describe`, `settings_get` | macctl's settings, their schema and current values |
| `settings_set` | Change a setting through macctl. A snapshot is taken first, risky settings need `confirm: true` after the user agrees, and `dry_run` shows the change without making it |
| `settings_undo`, `settings_history` | Roll back a change, newest first or by id, and list what changed |
| `checkpoint_list`, `checkpoint_create` | Summon's restore points |
| `crash_list` | Recent crash, hang and panic reports |
| `mac_events` | What changed on the Mac recently: offline, VPN, low disk, battery, running hot, displays |

`summon connect [agent...] [--dry-run]` registers the server with every agent it finds: Claude Code, Codex,
Cursor, OpenCode, Hermes, OpenClaw, Antigravity CLI (`agy`) and Pi. It also adds a short marked "This Mac" note to
each agent's always-loaded instructions file (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, ...). It uses an agent's
own `mcp add` when it has one, and otherwise edits its JSON config, keeping every other key. Each file is backed up
first to `~/.local/state/summon/backups/connect/`. Symlinked dotfiles are edited in place, and a second run changes
nothing. `summon disconnect` removes only Summon's server entry and note. OpenCode has no remove command, so that
step is printed for the user.

Claude Code, Codex, Cursor and the Antigravity CLI also get a session-start hook that runs `summon context --hook
<agent>`. It goes in `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.cursor/hooks.json` or
`~/.gemini/config/hooks.json`. Every new session then starts knowing this Mac's state without calling a tool. The hook
prints plain text for Claude Code and Codex, and the JSON shape Cursor and `agy` read. For Claude Code and Codex
the start hook also records the session in Activity, and a `SessionEnd` hook (`summon event hook end --agent <id>`)
closes it. The user's own hooks stay, and
disconnect removes only Summon's. Paths per agent: [research note](research/2026-10-25-agent-mcp-configs.md).

It also serves the resource `mac://context`. Setting ids are checked before they reach macctl, so an id that looks
like an option is refused. Add it by hand with `claude mcp add summon -- summon mcp`, or with the same command and
args in any client's MCP config. The Claude Code plugin declares it already.

### Claude Code plugin

[`plugin/`](../incubator/summon/plugin), loaded with `claude --plugin-dir incubator/summon/plugin`. It is optional now:
`summon connect claude` gives Claude Code the MCP server, the This Mac note and session hooks that record sessions
in Activity. The plugin no longer declares the server, so its tools never appear twice.

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

Code: [`macctl/`](../macctl). Overview: [its README](../macctl/README.md). `macctl --version` prints the SummonOS version.

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
- **Declared recovery contract:** `describe` (and `list --json`) states what undo can promise for each setting:
  `exact` (presence, type and value), `value` (AppleScript), `conditional` (wallpaper: file and display must still
  exist) or `compare_only` (sensitive keys), plus side effects undo cannot take back (restarts, logout, a created
  folder). `--dry-run` repeats the limits for the settings it would change.
- **Undo preview:** `undo [<id>] --dry-run` lists what undo would do to each change (`restore`, `delete`,
  `already_restored`, `hand_edited`, `cannot_restore`) and whether it would end in `partial_restore`. Writes nothing.
- **macOS version gate:** settings carry a `minimumOS`; on an older macOS `set`, `apply` and `diff` refuse them
  with `unsupported` before anything is read or written.
- **Key discovery:** `discover start` saves a private baseline of the usual System Settings domains,
  `discover diff` lists the keys that changed since (exact types) with a draft catalog entry. Read-only.
- **Built for agents:** `--json` (automatic in a pipe) prints one object per run with stable error codes
  and exit codes. `doctor` checks permissions without triggering a prompt and links to the right System
  Settings pane.
- **Profiles:** JSON files of desired values. `apply` is idempotent and restarts Dock, Finder or
  SystemUIServer once at the end.

Settings (39, full table in [`macctl/docs/settings.md`](../macctl/docs/settings.md)):

| Domain | Settings |
|---|---|
| Dock | autohide, tile size, show recents, orientation, minimize effect, autohide delay, magnification, magnified size, open-app dots, only open apps, autohide speed |
| Finder | show extensions, path bar, status bar, default view, hidden files, folders first, extension-change warning, search scope |
| Keyboard | key repeat, initial key repeat, press and hold |
| Screenshots | location, format, disable shadow, floating thumbnail, date in file names |
| Appearance | dark mode, scroll bars, menu icons (macOS 26+) |
| Desktop | wallpaper (every screen) |
| Windows | click wallpaper to reveal desktop, tile by edge drag, tile margins |
| Menu bar | menu bar agent and keyboard navigation (macOS 27+, hidden) |
| Documents | save new documents to iCloud, autocorrect |

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
| `install.sh` | One-line SummonOS install (Summon + macctl) from the newest release (never `edge` unless `--channel edge`), checksum-verified, or `--from-source`; offers `summon connect`; [`docs/install-ai.md`](install-ai.md) is the same for agents |
| `.github/workflows/release.yml` | On a `v*` tag: universal `summon`, `macctl` and Summon.app in one zip, `SHA256SUMS`, build attestation, a GitHub prerelease (ad-hoc signed preview). After every green Swift CI run on `main`: the same zip as the rolling `edge` prerelease |
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

CI ([`.github/workflows/swift.yml`](../.github/workflows/swift.yml)) runs once per PR and once per push to `main`
(a newer commit on a PR cancels its older run). It builds and tests every Swift package, including Summon's templates,
`examples/menubar-starter` and `examples/menubar-panel-starter`, on `macos-26` and on `macos-15` (the minimum OS,
built with Xcode 26). An informational Xcode 27 leg (public preview on `macos-26`) builds and tests `summon` and
`macctl` to catch macOS 27 SDK breaks; it never blocks a merge and skips when the image has no Xcode 27.
A docs-only change (`docs/**`, or `*.md` outside a Swift package and `.claude/`) skips the Swift jobs.
It also validates design skill structure, typechecks their Swift examples, runs tooling regressions, and checks that
`summon`, Summon.app and `macctl` carry the version in `VERSION`, and scans every tracked file for private values
(`tools/private-scan.sh` with the generic `tools/public-patterns.txt`: private IPv4 ranges, non-documentation MACs,
personal mail domains).
[`codeql.yml`](../.github/workflows/codeql.yml) runs CodeQL on the Swift in `summon` and `macctl` (PRs that touch
Swift, pushes to `main`, weekly); Dependabot (`.github/dependabot.yml`) bumps the SHA-pinned actions weekly.
[`release-smoke.yml`](../.github/workflows/release-smoke.yml) installs each published release on a clean `macos-26`
runner with the public one-line installer, then runs `summon --version`, `summon doctor`, `summon context --json`,
`macctl --version` and `macctl doctor`; it also runs by hand for any tag.
A second workflow, [`visual-qa.yml`](../.github/workflows/visual-qa.yml) (Visual QA (macOS)), runs on PRs that touch
`incubator/summon/**` and on demand: on GitHub-hosted `macos-26` and `macos-15` runners it opens the Summon panel
(⌃⌥Space) and menu bar panel, every Settings page (`summon://settings/<section>`), the Activity window and a sample
crash alert (`summon://test-crash`, allowed in release builds only when the `VisualQA` default is set) in light and
dark, and uploads screenshots as 14-day artifacts. It fails when a surface
does not open or a capture is missing or the wrong theme. It is not a merge gate.
