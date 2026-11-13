---
type: Reference
title: Summon command reference
description: "Every summon command: route, arguments, flags, examples and what each command prints."
tags: [cli, reference, summon]
---

# Summon command reference

`summon` is the CLI for the Summon menu bar app and the SummonOS control plane. Every route, argument, flag and example below matches the current checkout's command sources
(`incubator/summon/Sources/SummonCLI/`) and the command catalog
(`incubator/summon/Sources/SummonCore/CommandCatalog.swift`), which also drives `summon commands` and `summon commands --json`.

## How to read this reference

| Column | Means |
|---|---|
| **Route** | What you type after `summon`, for example `summon theme list`. |
| **Arguments** | Placeholders (`<name>`) and flags (`[--dry-run]`) exactly as the command accepts them. |
| **Example** | One invocation, taken from the command sources. |
| **Risk** | `read` changes nothing, `user` changes your settings or projects, `launch` starts a program (an agent, the panel, a terminal). |
| **Prints** | What the command prints, verified in source where the output is fixed; blank where it depends on runtime state. |

- Exit codes: `0` ok, `1` error, `2` missing dependency, `4` unsupported. Unknown commands and usage problems print usage to stderr and exit `1`.
- `summon` lives in `~/.local/bin`; add that folder to your shell's PATH if the installer did not.
- `summon version` prints `summon 0.2.5`; `summon doctor` checks the install and setup.

## Agents: launch, choose and connect

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `agent` | `[--inline] [--no-checkpoint]` | `summon agent` | Starts the default agent in a new terminal window, with a checkpoint first unless `--no-checkpoint`; `--inline` replaces this terminal with the agent instead of opening a new window. |
| `agent prompt` | `[--inline] <prompt...>` | `summon agent prompt "Why is my Mac slow?"` | Starts the default agent straight into a task. |
| `default agent` | `[claude\|codex\|opencode\|copilot\|cursor-agent\|agy\|pi\|hermes\|openclaw\|grok]` | `summon default agent claude` | Shows or saves the default coding agent. |
| `default terminal` | `[ghostty\|kitty\|terminal]` | `summon default terminal kitty` | Shows or sets the terminal agents open in (unset: first installed of Ghostty, kitty, Terminal). |
| `default execution` | `[normal\|unattended]` | `summon default execution unattended` | Shows or saves `normal` (leave the agent's own controls in place) or `unattended` (bypass supported agent approvals/sandboxing where the registry supports them); existing installs retain their saved choice. |
| `default repos` | `[always\|ask]` | `summon default repos` | `ask` (default): no repo until `summon project repo <name>` and its approval dialog; `always`: every new app gets a private GitHub repo right away. |
| `agents` | `[--json]` | `summon agents --json` | Lists the agents Summon knows, whether each is installed, and how to install it. |
| `agents install` | `<agent> [--yes]` | `summon agents install pi` | Installs a coding agent: bun for npm agents (npm if bun is missing), else the vendor's script; `--yes` off a terminal; relinks skills. |
| `agents update` | `[<agent>\|--all] [--check] [--refresh] [--yes] [--json]` | `summon agents update --check` | Updates each agent the way it was installed (brew, cask, bun, npm, vendor updater); `--check` lists method, current and latest version without changing the saved channel. Results are cached in `~/.local/state/summon/agent-updates.json`. |
| `agents status` | `<agent> [--json]` | `summon agents status pi --json` | Asks the agent's CLI whether it is logged in and which models it offers. |
| `agents login` | `<agent>` | `summon agents login codex` | Opens the agent's own login in a terminal window. |
| `agents set` | `<agent> [--model <m>\|--default-model] [--skills a,b\|--all-skills]` | `summon agents set claude --model opus` | Chooses an agent's model and which Summon skills it gets; saved in `~/.config/summon/agents.json`, relinked at once. |
| `agents defaults` | `[--skills a,b\|--all-skills]` | `summon agents defaults --skills summon,summon-mac,summon-art` | The All Agents skills every agent follows unless it has its own list. |
| `agents plugins` | `<agent> [--json]` | `summon agents plugins claude` | An agent's installed plugins (Codex: its MCP servers). |
| `agents plugin-add` | `<agent> <plugin>` | `summon agents plugin-add pi npm:context-mode` | Installs a plugin with the agent's own installer (a backup is kept). |
| `connect` | `[agent...] [--dry-run] [--json]` | `summon connect --dry-run` | Adds the summon MCP server and a "This Mac" note to the named agents (every supported target by default: Claude Code, Codex, Cursor, OpenCode, Hermes, OpenClaw, Antigravity CLI (`agy`), Pi). Backs up edited files first. |
| `disconnect` | `[agent...] [--dry-run] [--json]` | `summon disconnect pi` | Removes what `connect` added only; your other configuration stays. OpenCode's server removal is manual (its CLI has no remove command). |
| `mcp` | | `claude mcp add summon -- summon mcp` | Stdio MCP server for any client: 11 tools — `mac_context`, `settings_list`, `settings_describe`, `settings_get`, `settings_set`, `settings_undo`, `settings_history`, `checkpoint_list`, `checkpoint_create`, `mac_events`, `crash_list`. |

## The Mac, as agents see it

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `context` | `[--json\|--hook <agent>] [--only a,b]` | `summon context --json --only power,storage` | One read-only snapshot of this Mac: model, chip, RAM, macOS, power/thermal, storage, network/VPN, displays, appearance, frontmost app and window, running apps, permissions, installed agents, recent crashes. `--only` limits sections (`system,power,storage,network,displays,apps,appearance,permissions,agents,crashes`). |
| `context fields` | | `summon context fields` | Lists context fields and which are hidden. |
| `context hide` | `<field>` | `summon context hide window-title` | Hides a field from agents: hostname, window-title, running-apps, paths, selected-text, browser-page, finder-selection. |
| `context show` | `<field>` | `summon context show window-title` | Shows a hidden field again. |
| `events` | `[--json] [--limit N] [--kind settings\|agent\|checkpoint\|theme\|problem\|mac] [--follow]` | `summon events --kind mac --follow` | Activity timeline: settings changes, undos, checkpoints, agent sessions, themes, crashes, Mac changes; `--follow` prints new lines. |
| `event add` | `<kind> <title...> [--detail text] [--ref key=value]...` | `summon event add session.start "Claude Code session" --ref session=abc` | Records an event in the timeline. |
| `event hook` | `start\|end` | `summon event hook start < payload.json` | Records a Claude Code SessionStart/SessionEnd hook payload read from stdin. |

## Recovery: checkpoints and undo

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `checkpoint create` | `[--dry-run] [label]` | `summon checkpoint create before-cleanup` | Takes a checkpoint now (macctl snapshot marker plus git commit of `~/.config` when it is a repository). Prints `Checkpoint <id> "label": config commit <sha>, macctl marker <snapshot>` (`none` when absent). `--dry-run` prints the planned steps and takes nothing. |
| `checkpoint list` | `[--json]` | `summon checkpoint list --json` | Lists checkpoints newest first: `id  label  config:<8-char commit>  macctl:<snapshot>`. Prints "No checkpoints yet. One is taken every time `summon agent` starts." when empty. |
| `checkpoint undo` | `[id] [--dry-run]` | `summon checkpoint undo --dry-run` | Restores `~/.config` and covered macOS settings to a checkpoint (the latest when no id is given). `--dry-run` shows the plan and writes nothing. |
| `undo-session` | `[--dry-run]` | `summon undo-session` | Same as `checkpoint undo` of the latest agent session checkpoint. |

Checkpoint coverage is limited: supported macctl changes, successfully captured config, and explicitly recorded theme-created files. It is not a full-machine backup; see [security and recovery](security-model.md).

## Scheduled agent tasks

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `task new` | `[what you want] [--inline]` | `summon task new "every weekday at 9, check brew updates"` | Describes a recurring task to the default agent; it asks what is unclear, writes the run prompt and schedules it with a checkpoint. |
| `task add` | `<prompt> (--at HH:MM [--weekdays] \| --every <n>h) [--agent <id>] [--name <name>] [--execution normal\|unattended] [--directory <path>]` | `summon task add "Check brew updates and summarize" --at 09:00 --weekdays --agent claude` | Schedules a prompt for an agent, unattended via launchd; the result is recorded in Activity. Defaults to the default agent and `~/Summon`. |
| `task list` | `[--json]` | `summon task list --json` | Recurring tasks with their schedule and last result; empty: "No tasks. Add one: ..." |
| `task remove` | `<id>` | `summon task remove brew-check` | Stops and deletes a recurring task; its folder and logs stay. |
| `task run` | `<id>` | `summon task run brew-check` | Runs a recurring task now, unattended (what launchd calls); prints `Done. Log: <path>`. |

## Projects and templates

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `project new` | `<name> --kind menubar\|menubar-panel\|launcher\|hud\|notch\|app\|widget\|cli\|screensaver [--json]` | `summon project new mac-battery --kind menubar` | Copies a template to `~/Summon/Apps/<name>` and registers it in Summon's private list. A private GitHub repo is created right away only when `summon default repos always` is set; otherwise the command tells you to finish with `summon project repo <name>`. |
| `project register` | `<name> [--kind menubar\|app\|cli\|screensaver] [--json]` | `summon project register mac-network` | Registers an existing `~/Summon/Apps/<name>` folder. |
| `project import` | `<path> [--name <name>] [--kind menubar\|app\|cli\|screensaver] [--json]` | `summon project import ~/old-apps/mac-network` | Copies an external project into `~/Summon/Apps/` and registers it. |
| `project list` | `[--json]` | `summon project list --json` | Prints tab-separated `name  kind  path  repo` rows (`no repo` when none); empty: "No projects yet...". |
| `project path` | `[name]` | `summon project path mac-battery` | Prints a project's folder; without a name, prints `~/Summon/Apps`. |
| `project open` | `<name>` | `summon project open mac-battery` | Opens the project's built app (`build/<Name>.app`), otherwise reveals its folder. |
| `project forget` | `<name>` | `summon project forget mac-battery` | Removes the project from the private list only; its folder and repo stay. |
| `project repo` | `<name> [--owner <login>]` | `summon project repo mac-battery` | Creates the project's **private** GitHub repo with CI, only after you approve it in a native Summon dialog (`Create Private Repo`; Cancel is default). `project repo` has no flag that skips the dialog; with `summon default repos always`, new apps are approved without a per-project dialog. |
| `project shots` | `<name>` | `summon project shots mac-battery` | Builds the app, captures its panel or window into `docs/screenshots/`, adds them to its README and commits. |
| `showcase` | `[--no-open]` | `summon showcase` | Writes `~/Summon/Showcase/index.html`, a gallery of every app Summon made, and opens it. |

Projects are private to this Mac (`~/.config/summon/projects.json`), never in the workspace registry (`plugins.json`). Nine starter kinds exist; `menubar-panel`, `launcher`, `hud` and `notch` record as menu bar apps, `widget` as a window app.

## Look and feel

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `theme list` | `[--json]` | `summon theme list` | Installed themes, the current one marked with `*`; broken theme files are skipped there (use `theme check`). |
| `theme current` | | `summon theme current` | Prints the current theme slug. |
| `theme set` | `<slug> [--no-wallpaper]` | `summon theme set summon-night` | Takes one checkpoint first, then applies macOS appearance, wallpaper and accent through macctl (undoable) and writes terminal/editor configuration files. Prints `Undo the whole look: summon checkpoint undo <id>`. |
| `theme check` | `<slug>` | `summon theme check hearts-valley-theme` | Validates `theme.json` (#RRGGBB colors, 16 terminal colors) and reports contrast/color recommendations without changing the palette. |

## Diagnostics and housekeeping

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `doctor` | `[--json] [--fix]` | `summon doctor --json` | Checks Summon's install and setup (app, CLI, config, macctl, event log, hotkeys, permissions, skill links); exits nonzero for failed checks, warnings alone do not fail it. |
| `fix` | `[--apps] [--inline]` | `summon fix --apps` | Launches the default agent for Mac diagnostics; `--apps` limits it to My Apps repair items (excludes recommendations), with a checkpoint. |
| `crash list` | `[--json] [--limit N]` | `summon crash list --json` | Recent crash, hang and panic reports, newest first, muted programs skipped. |
| `crash show` | `<file.ips> [--json]` | `summon crash show "~/Library/Logs/DiagnosticReports/Foo.ips"` | Prints the parsed facts of one report. |
| `crash diagnose` | `<file.ips>\|--latest` | `summon crash diagnose --latest` | Hands a report to the default agent with the `diagnose-crash-mac` skill. |
| `crash mute` | `[program] [off]` | `summon crash mute Foo` | Stops crash notifications for one program (`off` unmutes); no argument lists muted programs. |
| `debug` | `[--print] [--save] [--since 1h]` | `summon debug --print --since 30m` | Collects a debug bundle: macOS version, hardware, recent errors, reports, packages, with best-effort redaction; review the saved bundle before sharing. |
| `update` | `[--channel stable\|edge] [--check] [--yes]` | `summon update --check` | Updates Summon and macctl from GitHub releases (`stable`: numbered tags including previews; `edge`: the rolling artifact), checksum- and signed-provenance-verified (recent `gh` required in this candidate), rolls back on failure, then runs `summon doctor`. `--check` only reports; the chosen channel is remembered in `~/.config/summon/defaults/channel`. |
| `clean` | `[--apply] [--if-due] [--quiet] [--json]` | `summon clean` | Previews tidying `~/Summon`: old task logs, untouched art jobs, Antigravity originals go to the Trash; apps are never touched. `--apply` performs it and reports failures. |
| `home` | `[--quiet]` | `summon home` | Sets up `~/Summon` (Apps, Art, Tasks, a Themes link, `.gitignore`) and migrates older Summon files into it; prints the home path and any moved files. |
| `status` | `[--json]` | `summon status` | Agent, macctl, last change, last checkpoint and recent problems at a glance. |
| `path` | | `summon path` | Prints the folder holding Summon's shared files (themes, skills, wallpapers): `$SUMMON_PATH`, else `<binary>/../share/summon`, else the folder holding the binary. |
| `hooks` | `list` \| `run <theme-set\|post-login\|post-update\|wake\|crash> [args...]` | `summon hooks list` | Lists hook scripts per event (`theme-set`, `post-login`, `post-update`, `wake`, `crash`); `hooks run` runs the hooks of one event. |

## Menus, panel, icons, skills

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `menu init` | `[--force]` | `summon menu init` | Writes the default menu tree to `~/.config/summon/menu.jsonc` if it does not exist. |
| `menu list` | `[--json]` | `summon menu list --json` | Prints the Summon Menu tree. |
| `menu summon` | `[id]` | `summon menu summon style.theme` | Opens the menu bar panel, optionally at one entry. |
| `panel` | `[--close]` | `summon panel` / `summon panel --close` | Opens or closes the menu bar panel without activating Summon. |
| `icon set` | ` <path>` | `summon icon set ~/Pictures/work.png ~/Summon` | Puts a custom icon on any file, folder or app. |
| `icon reset` | `<path>` | `summon icon reset ~/Summon` | Removes a custom icon. |
| `skills` | | `summon skills` | Lists the skill files Summon ships. |
| `skills link` | `[--quiet]` | `summon skills link` | Links Summon's skills into each installed agent's skill folders, keeping your own folders and symlinks. |

## Shared agent-plugin catalog

These are agent extensions, not the native-app workspace registry in `plugins.json`.

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `plugins` / `plugins list` | `[--json]` | `summon plugins list --json` | Lists the shared catalog and installed status for installed agents with a compatible build. |
| `plugins install` | `<id>` | `summon plugins install <id>` | Installs the catalog entry into compatible installed agents; skips installed copies and reports per-agent failures as warnings. Inspect the output, not only the exit code. |
| `plugins fix` | `<id> <agent> [--inline]` | `summon plugins fix <id> claude --inline` | Starts the default agent with a repair prompt and checkpoint for that extension and target agent. |

## Catalog and version

| Route | Arguments | Example | Prints / does |
|---|---|---|---|
| `commands` | `[--json]` | `summon commands --json` | Lists every command with arguments and examples (plain text or JSON). |
| `version` | | `summon version` / `summon --version` | Prints `summon 0.2.5` (the shared SummonOS base version; `macctl --version` prints `macctl 0.2.5`). |

## Commands that print JSON

`--json` emits the route's JSON value with sorted object keys, not a universal object envelope. Lists such as `agents`, `plugins`, `project list`, `task list` and `theme list` emit arrays; diagnostics such as `doctor` emit objects. Other supported routes include `agents status`, `agents plugins`, `agents update`, `checkpoint list`, `context`, `crash list`, `crash show`, `events`, `status`, `connect`, `disconnect`, `clean`, `menu list`, and project creation/registration/import. Some routes pretty-print over multiple lines, so parse the complete JSON value rather than treating each line as an independent event. Help (`--help`), version output and parser errors are plain text.

## Where commands live

Command implementations are in `incubator/summon/Sources/SummonCLI/` (one file per command family: `AgentCommands.swift`, `ConnectCommands.swift`, `ContextCommands.swift`, `CrashCommands.swift`, `DoctorCommand.swift`, `DebugCommands.swift`, `ProjectCommands.swift`, `ThemeCommands.swift`, `TaskCommands.swift`, `UpdateCommand.swift`, `PanelCommand.swift`, `MenuCommands.swift`, `IconCommands.swift`, `ShotCommands.swift`, `MCPCommand.swift`, `ActivityCommands.swift`) and the catalog is generated from `incubator/summon/Sources/SummonCore/CommandCatalog.swift`. None of this reference describes behavior that is not in those sources.