# Features

Everything each project in this workspace can do today, in one place. "Planned" marks what is designed
but not built. Keep this page current: a PR that adds or removes a user-visible feature updates it
([`AGENTS.md`](../AGENTS.md#how-we-work), step 7).

- [Summon](#summon): one coding agent you summon from anywhere on the Mac
- [macctl](#macctl): read, set, diff, apply and undo macOS settings
- [mac-network](#mac-network) and [mac-calendar](#mac-calendar): shipped menu bar apps
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
  folder and keeps any folder of yours. Install and every app launch run it.
- **Starts in `~/Summon`:** an agent launched from `~` or `/` starts in the projects folder.

### Safety: checkpoints and undo

- **A checkpoint before every agent session:** a `macctl` snapshot marker plus a git commit of
  `~/.config` (`summon checkpoint create`).
- **Undo:** `summon undo-session` (or `summon checkpoint undo [id]`) restores `~/.config` and every macOS
  setting changed since. `--dry-run` shows the plan first. `summon checkpoint list` lists them.

### The Mac calls the agent

- **Crash watcher:** the menu app notifies you about new crash, hang and panic reports. The notification
  hands the report to the agent with the `diagnose-crash-mac` skill.
- **Crash commands:** `summon crash list`, `crash show <file.ips>` (parsed facts), `crash diagnose
  --latest`, `crash mute <program>` (and `off`), with muted programs managed in Settings.
- **Debug bundle:** `summon debug [--print] [--save] [--since 1h]` collects the macOS version, hardware,
  recent errors, reports and packages.

### Summon Menu (⌃⌥Space)

A searchable, keyboard-first launcher defined in `~/.config/summon/menu.jsonc` (`summon menu init`,
`menu list`, `menu summon [id]`). Entries can be hidden, checked or disabled by shell guards. Default
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
  - Agents: the default agent, install links; per agent its account (logged in or not, Log In…), its model
    (suggestions from the agent's real model list) and its skills, each with its description.
  - Terminal: which terminal agents open in.
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

### Recurring agent tasks

- Describe it, the agent sets it up: `summon task new "every weekday at 9, check brew updates"` (or Summon Menu ›
  Agent › Schedule a Task…, or "summon, every morning…" in any agent chat). The agent asks what is unclear, writes
  a complete run prompt (it runs unattended), and adds the task.
- Directly: `summon task add "<prompt>" --at 09:00 [--weekdays]` or `--every 2h`, optionally `--agent <id>` and
  `--name`; `summon task list`, `summon task run <id>`, `summon task remove <id>`.
- Settings › Tasks shows each task (schedule, agent, last result), view only.
- Each task is a LaunchAgent that runs the agent unattended (its print mode) in `~/Summon`, after a
  checkpoint, for at most 30 minutes. Every run leaves a log in `~/.local/state/summon/tasks/<id>/`, a line
  in Activity (failed runs in red) and a notification.

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
  and `undo [<id>]`, which also deletes keys that were unset before.
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

## The workspace

What this repo gives you for building more apps ([`README.md`](../README.md), [`docs/tools.md`](tools.md)).

| Tool | Does |
|---|---|
| `tools/mp` | Plugin registry: `new`, `promote`, `clone`, `list`, `status`, `index`, `adopt` |
| `tools/publish-public.sh` | Clean snapshot of a dev repo to its public repo; refuses on private values |
| `tools/release.sh` | Zipped `.app` on the public repo's Releases |
| `tools/render-previews.sh`, `tools/xcode-mcp.ts` | SwiftUI previews to PNG through the Xcode MCP bridge |
| `tools/check-workspace.sh` | Hygiene gate: package locations, file sizes, `plugins.md` up to date |
| `tools/install-skills.sh` | Links the workspace skills into `~/.claude/skills` |
| `tools/readme-art.py`, `tools/record-demos.sh` | README art and recorded terminal demos |

| Skill | Use |
|---|---|
| `MacAppArchitecture` | App shape, layers, state, concurrency, backend calls, storage, system tools |
| `MacUX` | Views, panels, windows, menu bar items, activity feeds, HIG, polish review |
| `MacAppBuild` | Scaffold, build, previews, verify, release |
| `MacSetup` | Configure a Mac with `macctl` |
| `PortLinuxWidget` | Port a Linux widget or script to a native Mac app |
| `swiftui-expert-skill`, `swift-concurrency-pro` | Vendored (MIT): SwiftUI and Swift concurrency depth |

CI ([`.github/workflows/swift.yml`](../.github/workflows/swift.yml)) builds and tests every Swift package
on macOS on every push, including Summon's templates and `examples/menubar-starter`.
