---
type: Reference
title: Features
description: "Every user-visible feature of Summon, macctl, the SummonOS apps and the workspace tools, in one list."
tags: [features, summon, macctl]
---

# Features

Current-checkout feature reference, audited on 2026-11-11. The shared base version in `VERSION` is **0.2.4**;
the tagged 0.2.4 baseline is commit `3f37adf`. Later runtime hardening, native About, My Apps inventory and accent
changes below are **unreleased branch implementation**, not proof a downloaded 0.2.4 build contains them.
See the [changelog](../incubator/summon/CHANGELOG.md) and
[runtime audit's historical evidence and remaining acceptance](plans/2026-11-08-runtime-audit.md#implementation-evidence-and-unverified-acceptance-2026-11-08).
Implemented behavior is not a claim of completed profiling, retained-memory or accessibility acceptance.
"Planned" marks work not built. A PR that changes a user-visible feature updates this page
([`AGENTS.md`](../AGENTS.md#how-we-work), step 7).

- [Summon](#summon): one coding agent you summon from anywhere on the Mac
- [macctl](#macctl): read, set, diff, apply and undo macOS settings
- [mac-network](#mac-network), [mac-calendar](#mac-calendar), [mac-breathe](#mac-breathe) and [end-of-day](#end-of-day): apps built with SummonOS
- [The workspace](#the-workspace): tools, skills and templates for building more apps

## Summon

Code: [`incubator/summon/`](../incubator/summon). Overview: [its README](../incubator/summon/README.md).

### Summon the agent

- **Ten launchable agents:** Claude Code (`claude`), Codex (`codex`), OpenCode (`opencode`), GitHub Copilot
  (`copilot`), Cursor CLI (`cursor-agent`, alias `cursor`), Antigravity (`agy`), Pi (`pi`), Hermes (`hermes`),
  OpenClaw (`openclaw`) and Grok (`grok`). `summon default agent <id>` chooses one; `summon agents` shows which
  are installed and how to install the rest. Automatic MCP connections use a separate eight-target registry
  ([below](#every-agent-the-mcp-server)); launch support does not imply connector or scheduled-task support.
- **Install and update agents:** `summon agents install <agent>` prefers the vendor script when one is registered
  (including OpenClaw); other npm-published agents use bun, then npm, or print the bun installation hint if neither
  exists. Vendor scripts need confirmation (`--yes` off a terminal). `summon agents update <agent>|--all` uses
  the detected installation method (Homebrew formula/cask, bun, npm or vendor updater); `--check` lists
  method, current and latest version, cached for 24 hours in `~/.local/state/summon/agent-updates.json`.
  `summon agents` shows the install method. Skills are relinked after every install or update.
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
turns each one off. Crash diagnosis, Activity and tasks keep their own prompts. Permission-dependent fields
can be absent; listing the feature is not browser-automation or accessibility acceptance evidence.

### Safety: checkpoints and undo

- **Execution policy:** Settings › General › Agent execution or `summon default execution normal|unattended`.
  New installs use the agent's own controls; existing configured installations retain unattended execution.
  The [security model](security-model.md) explains the authority and recovery boundaries.

- **A checkpoint before agent sessions by default:** a `macctl` snapshot marker plus a git commit of
  `~/.config` when it is already a repository (`summon checkpoint create`). `summon agent --no-checkpoint`
  explicitly skips capture. Capture failures remain visible; scheduled work stops before launching its agent
  if capture reports a failure.
- **Undo:** `summon undo-session` (or `summon checkpoint undo [id]`) restores successfully captured config files
  and supported macctl settings changed since. Ordinary new files and external actions are excluded. Files
  explicitly recorded as created by a theme are the exception: undo removes those, and recorded folders only
  when they contain nothing else. `--dry-run` shows the plan; `checkpoint list` includes capture problems.
  Existing editor-theme files outside captured `~/.config` are not backed up by this mechanism.
- **MCP settings sessions get a checkpoint too:** before a client's first real `settings_set` through
  `summon mcp`, Summon creates a checkpoint labelled "&lt;Agent&gt; via MCP", using the MCP `clientInfo` name.
  Successful tool replies include its undo command, and Activity offers **Undo This Session…**. This covers
  supported settings/captured config, not every action that agent performed elsewhere in the session.
- **Panel:** after an agent session from the last 12 hours that changed settings, the panel shows one row, "Undo
  &lt;Agent&gt; Session (N changes)…". Choosing it asks first, then runs `summon checkpoint undo`. The row disappears
  when there is nothing to undo.

### The Mac calls the agent

- **Crash watcher:** the menu app announces new crash, hang and panic reports, as a macOS notification (default)
  or a Summon alert (Settings › Notifications), never both; the panel shows no crash row. The alert never takes the keyboard from the app you
  are typing in; a burst shows one alert ("N more"), banners group per program. Diagnose with AI hands the report
  to the agent with the `diagnose-crash-mac` skill.
- **Task results:** each scheduled run records one identified terminal outcome (done, failed, cancelled,
  timed out or interrupted), including failures before the agent starts. Summon announces recorded results with
  Show Log and Ask Agent; the CLI uses a bounded fallback banner when the app cannot deliver them. A failed
  notification never rewrites an execution result. Full output stays in the private log; the event summary is
  bounded, including encoded Unicode and escaped text.
- **Crash commands:** `summon crash list`, `crash show <file.ips>` (parsed facts), `crash diagnose
  --latest`, `crash mute <program>` (and `off`), with muted programs managed in Settings.
- **Siri, Shortcuts and Spotlight:** Summon's App Intents. "Ask Summon" starts your agent with what you said;
  "What needs updating in Summon" reads the pending updates; "Update everything with Summon" installs them and opens
  the Updates window; "How's my Mac in Summon" reads battery, free space, network and recent crashes; "Run <item>
  in Summon" runs a Summon Menu item. Each is also a Shortcuts action. Builds need Xcode for the metadata.
- **Debug bundle:** `summon debug [--print] [--save] [--since 1h]` collects the macOS version, hardware,
  recent errors, reports and packages, with best-effort redaction and private saved files. Review before sharing.

### Summon panel and Summon Menu (⌃⌥Space)

The menu bar panel (⌃⌥Space) with the Summon Menu opens under the Summon icon from a left click, ⌃⌥Space, `summon panel` or
`open -g summon://panel` (`summon panel --close` closes it). It takes typing without taking focus from the app
you're in, and Esc returns you there. Right-click the icon for Settings… and Quit. Pressing ⌘↵ anywhere in the
panel immediately launches the default agent in your preferred terminal in `~/Summon`.
When **Show agent time in the menu bar** is enabled in Settings › General › Menu Bar, an active session's elapsed
time (`mm:ss`) appears next to the Summon icon, including while the panel is closed; its accessibility label
includes the agent and elapsed time. The panel emits an accessibility announcement when opened by hotkey or URL.
These are implemented accessibility affordances, not completed VoiceOver acceptance.

At the top of the panel is the Summon Menu: a searchable, keyboard-first menu tree defined in
`~/.config/summon/menu.jsonc` (`summon menu init`, `menu list`, `menu summon [id]`, which opens the panel at that
entry). There's no separate launcher window. Entries can be hidden, checked or disabled by shell guards.
My Apps uses the same six categories in the menu panel and Settings: Panel Apps, Themes, Art & Wallpapers,
Window Apps, Command-Line Tools and Screensavers. Empty categories remain visible with an empty state.
Registered projects (`~/.config/summon/projects.json`), all built-in/custom themes and art jobs are included.
Repair totals count unique inventory items with operational defects, not individual diagnostics or stale health
entries. Category badges and Settings use the same summary. My Apps' Fix with AI targets exactly those repair
items (`summon fix --apps`), not the separate general Mac diagnostics handled by `summon fix`.

Theme contrast measurements and terminal-hue preferences are recommendations, with all findings available in
Settings' Review details and panel tooltips. Palette-only themes need no wallpaper; missing *referenced* images
remain repair defects. Optional app icons/showcase screenshots are recommendations too. Preset colors are not
automatically changed. Build detection recognizes PascalCase app/saver bundles and real CLI executables in
SwiftPM's external cache; an empty `.build` directory is not proof of a built tool.

Projects open their built `.app` or project folder; CLI/saver entries reveal their project folder. Themes apply
the selected palette; art entries open their folders. Built-in menu groups (search or Settings › Setup exposes
groups not shown on the home panel):

| Section | Entries |
|---|---|
| Agent | Ask Agent, Schedule a Task…, Diagnose Last Crash, Fix Issues with AI, Save Debug Bundle, Undo Last Agent Session, Default Agent (the built-in submenu lists eight agents; Settings/CLI use the ten-agent registry) |
| My Apps | All six app/theme/art categories, with shared repair counts and separately identified recommendations |
| Style | Theme, Dark Mode, Light Mode, Start Screensaver |
| Setup | Show Profile Drift, Check Permissions, Fix Issues with AI, Edit This Menu, Open Hooks Folder, System Settings |
| Trigger | Screenshot Area, Screenshot to Desktop, Stay Awake for 1 Hour, Lock Screen |
| Make Something | New Menu Bar App, New Launcher, New Floating HUD, New Notch App, New App, New Widget, New Command-Line Tool, New Screensaver, New Theme, New Wallpaper, New Icon |
| Install | Ghostty, kitty, AeroSpace Tiling, Window Borders (each only when missing) |
| Update | Opens the Updates window; Check for macOS Updates remains in the default menu data |
| System | Sleep, Restart…, Log Out…, Shut Down… |

### Menu bar app

- **Panel** (320 pt, Liquid Glass on macOS 26): the header shows Summon, the default agent and its running state,
  plus an updates badge when updates are available. Then come **Search Summon…**, **Ask Agent**,
  **Make Something ›**, **My Apps ›**, and **Update** when updates are pending. A setup-problem status line
  appears only when Summon's doctor reports problems; it opens Fix with AI. Crashes are notifications, not a
  panel row. An undo row appears when there is something to undo, followed by Activity…, Settings… (⌘,) and
  Quit Summon (⌘Q). Search reaches the whole Summon Menu (Style, Setup, Trigger, Install, Update, System, Agent);
  Settings › Setup exposes the setup groups with Run buttons. With no default agent, the header offers
  "Choose an agent". The menu bar normally shows only Summon's icon; the agent clock is optional.
- **Open and refresh:** the panel presents its last valid menu immediately and keeps one shared Activity refresh
  interest while open. File watches wake changed logs and crash reports; hidden panels do not run the visible
  one-second guard/activity loop. `summon://menu/<id>` resolves a newly added entry after its disk reload.
- **Welcome window** (first launch only, 720 × 480, close only): a brand header and what Summon does; choose the
  default agent from rows showing each agent's login (Log In… when logged out) or how to install one; allow
  Accessibility with a live check (Skip while off; one click re-grants after an update); then try ⌃⌥Space and
  watch it tick green, with a warning when the menu bar hides the icon; Done opens the panel. Closing it
  skips setup. An update where an agent is set and Accessibility is on never shows it. Settings › General › Show
  Welcome Again or `open summon://welcome` brings it back.
- **Undo confirmation:** "Restore N Changes" names what it does; Cancel is the default button.
- **Activity window:** a plain, oldest-first log of settings changes, undos, agent sessions, themes and
  crashes and recurring tasks, opened at the newest line (also `summon://activity`). Select lines and ask the agent about them
  from the bar at the bottom. Right-click a line to Ask, Copy, Diagnose, Show in Finder, or Undo This
  Change / Session.
- **Settings window** (⌘, or `summon://settings[/<section>]`): one close-only sidebar window with a searchable
  sidebar, page icon/title and grouped forms. Sections:
  - General: Accessibility (On or **Allow…**, with a two-second recheck while off), default agent and terminal,
    Start at login, workspace reveal, update preferences, About, agent execution, private-repo policy,
    cleanup, optional menu bar clock, configurable panel/agent hotkeys and Show Welcome Again. An older
    ad-hoc build's Accessibility entry may need its switch turned off and on again.
  - Agents: a list of agents (status dot, Default) with **All Agents** on top: the default agent, where agents
    open (Ghostty, kitty or Terminal), the skills every agent gets, what agents see about this Mac (computer name,
    window title, running apps, file paths: all on, each can be turned off), and shared plugins (OpenLTM: Install in All).
    Each agent's page has the same sections: Account (Connected, or Log In…), Model (from that agent's real model
    list, or Custom…), Skills (same as All Agents, or Custom), Plugins (installed, recommended, Add).
  - My Apps: the same complete app/theme/art inventory and repair count as the panel, including built-in themes; recommendations are separate and expandable.
  - Terminal: the default terminal, launch behavior and window styling.
  - Notifications: crash and hang alerts (Summon alert or macOS banner), task results, sound, muted programs with Unmute.
  - Appearance: the theme.
  - Setup: built-in menu setup/action groups with Run buttons.
  - Tasks: each recurring task with its schedule, agent and last result (view only).

- **About Summon:** Settings › General and the standard application About command share the native AppKit panel.
  It shows the base version, numeric build, revision, channel, configuration and UTC build time; a development
  build says when revision or time is unknown. The panel does not start an update or network check.

### Activity and status from the command line

- `summon status`: agent, macctl, last change, last checkpoint and recent problems at a glance.
- `summon version` (or `--version`): prints the SummonOS version (`summon 0.2.4`); `summon doctor` shows it on its
  first line and in `--json`. One version for `summon`, Summon.app and `macctl`, kept in the root `VERSION` file.
- `summon context [--json] [--only a,b]`: this Mac for agents in one read-only snapshot: model,
  chip, RAM, macOS, power and thermal state, free space per volume, network and VPN, displays, frontmost app and
  window, running apps, appearance, what the asking process may do (Accessibility, Screen Recording, Full Disk
  Access), installed agents and crashes in the last day. `summon context hide|show <field>` (or Settings › Agents)
  turns off the computer name, window title, running apps or file paths.
- `summon events [--kind settings|agent|checkpoint|theme|problem|mac] [--limit N] [--follow]`: the same timeline as
  the Activity window; `--follow` keeps printing new lines, so an agent can watch the Mac.
- **Live Mac events:** while Summon.app runs, its lightweight watch loop checks Mac vitals approximately once a
  minute (with scheduling slack) and logs changes as `mac.*` events. Events cover network offline/online, VPN,
  low disk space (under 20 GB)/recovery, low (below 20%) or very low (below 10%) battery, and thermal changes.
  Only crossings are logged, not the same state every minute. Agents read them with MCP `mac_events` (one of
  the 11 tools) or `summon events --kind mac --follow`. `summon event add` and `event hook start|end` let tools
  write to Activity; connected Claude Code/Codex hooks record their sessions there.
  The event mapper also supports display-count changes, but the normal periodic vitals probe does not collect
  displays; do not rely on that watch loop to emit display-connect/disconnect events.
- **Fix with AI** (`summon fix`) hands the agent current general diagnostics and eligible recent crashes,
  marking crash reports as seen so repeated requests do not diagnose the same reports again. The separate
  `summon fix --apps` action uses only My Apps' counted repair items.
- `summon doctor`: checks Summon's own install (app, CLI, config, macctl, event log, hotkeys,
  permissions, skill links) with a fix for each failure.
- `summon update [--channel stable|edge] [--check] [--yes]`: updates Summon and macctl from GitHub. `stable`
  selects the highest semantic-version `v*` tag in the returned release list, including preview/prerelease tags,
  never `edge`; it installs only a newer version. `edge` follows the rolling prerelease and installs when its
  version differs. Successful push CI on `main` triggers edge publication, but a failed/stale publication can
  leave that asset behind current source; do not assume it includes this branch. The display format is
  `<VERSION>-edge.<sha>`. Updates verify the zip against `SHA256SUMS`, use the release's staged installer and
  run `summon doctor`. `--check` only reports and does not save a channel choice. An explicit channel without
  `--check` is saved in `~/.config/summon/defaults/channel`, even before an install prompt. The CLI asks before
  installing unless `--yes`; without a terminal, `--yes` is required. A logged-in `gh` is the API fallback.
- The app checks at launch, then when 24 hours have elapsed since the previous check, while automatic checks
  are enabled and Low Power Mode is off. Checks include Homebrew
  (`brew outdated`), bun and npm globals (agent CLIs among them shown as Agents) and macOS (`softwareupdate -l`).
  The **Updates window** (the panel's Update row under Make Something, its "N updates" badge, or a notification)
  lists Summon's card (What's New, Install and Relaunch:
  the same install as `summon update`, then Accessibility again), then Agents, Homebrew, bun & npm and macOS. Each
  row shows current → new and installs on its own (Waiting…, Updating…, ✓ Updated; a failure shows Show Details
  with the output, Fix with AI (the agent gets the command and its output) and Retry, or Open in Terminal when it needs a password). Update All per section and in the
  toolbar, Check Now, "Checked N min ago"; right-click for What's New and Skip This Version. One notification per
  new set of updates, with Update All and Show. Settings › General › Updates: Check for updates automatically,
  the channel (Stable / Edge), Check per group, and Update agents automatically (`~/.config/summon/update-preferences.json`).

### Themes and look

- **Nine themes:** Summon Night (default) and Summon Dawn, plus seven community palettes (Tokyo Night,
  Catppuccin, Gruvbox, Nord, Rosé Pine Dawn, Kanagawa, Everforest), each with 5K wallpapers.
- **One command restyles everything:** `summon theme set <slug>` sets macOS dark or light mode, the wallpaper
  and the accent color (all through `macctl`, so they can be undone). It also restyles Ghostty, kitty, window
  borders and Claude Code, VS Code and Cursor through a "Summon" color theme (choose it once), and Neovim
  (`:colorscheme summon`, written when `nvim` is installed). It takes one checkpoint first and ends with
  `summon checkpoint undo <id>`. Undo restores captured `~/.config` files and supported macctl settings, and
  removes newly created files recorded by the theme (generated configs and editor themes). A folder containing
  added user files stays. Existing editor-theme files outside captured `~/.config` have no prior-content backup;
  arbitrary hook effects are not covered. The panel offers "Undo Theme <name> (N changes)…".
  There is also `theme list` and `theme current`. Settings › Appearance provides full 16:9 wallpaper previews, color swatches, one-click Apply, and an Undo button to revert to the previous theme.
- **Live accent synchronization:** Summon's controls use the active theme's exact accent; macOS uses the nearest
  system palette color. `macctl` notifies running apps after apply and undo. Finder folders set to Automatic follow
  that system accent; explicit folder colors/custom icons are preserved. Apps that cache colors may need reopening.
  Catppuccin now uses its mauve (`#cba6f7`) for the accent and active border; its remaining palette is unchanged.
  Theme checkmarks and Apply state follow the active theme, not a preview selection or stale shell guard.
- **Default terminal with auto-installer:** Settings › Terminal lets you select Ghostty, kitty, or Apple Terminal. If Ghostty or kitty is not installed, install it directly with one click via Homebrew.
- **Custom icons** on any file, folder or app: `summon icon set <image> <path>`, `icon reset`.
- **Hooks:** scripts in `~/.config/summon/hooks/<event>.d/` for `theme-set`, `post-login`,
  `post-update`, `wake` and `crash` (`summon hooks list`, `hooks run`).
- **Desktop layer (optional, Homebrew):** AeroSpace tiling with an ⌥ keymap (⌥1…9 workspaces,
  ⌥H/J/K/L focus, ⌥⇧H/J/K/L move, ⌥Return Ghostty), JankyBorders, Ghostty with a drop-down quick
  terminal, a Nerd Font, and shell aliases `a` / `ap` for the agent ([`config/`](../incubator/summon/config)).

### Make things: projects from templates

- `summon project new <name> --kind menubar|menubar-panel|launcher|hud|notch|app|widget|cli|screensaver` copies a template to `~/Summon/Apps/<name>`,
  runs `git init` with a first commit, and records it in a private list (`~/.config/summon/projects.json`).
  Also `project list`, `project path`, `project open`, `project forget`. `project register <name>` registers
  an existing `~/Summon/Apps/<name>` folder; `project import <path> [--name <name>]` can copy an external project
  into that home and register it. `--kind menubar|app|cli|screensaver` overrides kind detection for those commands.
- **Templates:** menu bar app, menu bar app on an `NSPanel` (opens from code, takes typing without stealing focus),
  command launcher (⌥Space by default, never ⌘Space; a pre-warmed Spotlight-style bar with fuzzy app search,
  ⌘1–9, ⌘K actions and file drop), floating HUD (an always-on-top stopwatch pill that never takes focus, thrown to
  the nearest corner, right-click opacity, size and corner), notch app (a drop shelf that grows out of the camera
  housing, with a fallback on screens without one), window app, desktop widget (a WidgetKit countdown set with
  Edit Widget, small and medium, plus the app that carries it; the one template with a small Xcode project,
  because only Xcode builds the widget extension), CLI tool, screensaver: the one set of templates,
  also used by `tools/mp new` for workspace plugins. Each follows its page in [UX surfaces](ux-surfaces/index.md).
  The launcher and HUD record their global shortcut in Settings (Carbon `RegisterEventHotKey`, no permission
  prompt, system shortcuts refused); the agent apps keep a small menu bar menu that Settings can hide.
  Every template's Settings window is close only (minimize and zoom dimmed, no full screen) and 480 pt wide. The
  window app has an inspector (⌥⌘I), ⌘F search, row context menus and undoable deletes, from 800 × 550; the
  `NSPanel` menu bar app has a right-click menu and "Show in menu bar". Both have a first-run welcome window
  (640 × 440, once, closing skips, Settings shows it again) with permission cards that check live status.
  Each has Core tests, README, MIT LICENSE, `PROJECT-CONTEXT.md`, `scripts/check.sh` and `scripts/test.sh`.
  The test wrapper supports Command Line Tools; the widget's full bundle/check gate requires Xcode for its
  embedded extension. The app kinds also share a kit: system-menu
  rows for panels, the Summon theme's accent (follows `summon theme set` live), Liquid Glass controls on macOS 26
  with a material on 15, Open at Login in Settings, a placeholder app icon, and `--screenshot` for
  `summon project shots` ([`templates/`](../incubator/summon/templates)).
- **GitHub only when you say so:** by default (`summon default repos` is `ask`) a new app gets no repo.
  `summon project repo <name>` creates a private repo (screenshots, CI, first push) only after you click Create in
  a native dialog; Cancel is the default button, and no flag skips the dialog. Turning on Settings › General ›
  "Create a private GitHub repo for every new app" (`summon default repos always`) makes every new app get one
  right away, without the dialog. Never public.

### Every agent: the MCP server

`summon mcp` is an MCP server on stdio for clients that support that transport, including clients without a
Summon launch entry. It is native Swift with no package dependencies. The current
[`SummonMCP.tools`](../incubator/summon/Sources/SummonCore/SummonMCP.swift) declares **11 tools**:

| Tool | Does |
|---|---|
| `mac_context` | The `summon context` snapshot (all sections or some) |
| `settings_list`, `settings_describe`, `settings_get` | macctl's settings, their schema and current values |
| `settings_set` | Change a setting through macctl. A snapshot is taken first, risky settings need `confirm: true` after the user agrees, and `dry_run` shows the change without making it |
| `settings_undo`, `settings_history` | Roll back a change, newest first or by id, and list what changed |
| `checkpoint_list`, `checkpoint_create` | Summon's restore points |
| `crash_list` | Recent crash, hang and panic reports |
| `mac_events` | Recent recorded Mac events; the app's periodic watch supplies network/VPN, disk, battery and thermal transitions |

`summon connect [agent...] [--dry-run]` has **eight automatic targets**: Claude Code, Codex, Cursor, OpenCode,
Hermes, OpenClaw, Antigravity CLI (`agy`) and Pi. Copilot and Grok remain launchable without automatic connectors.
Presence is detected from binaries or supported config/app markers. Connect uses the agent's own `mcp add`
where available, otherwise edits its JSON `mcpServers` map while retaining other keys. It adds a marked
"This Mac" note only for targets with a supported always-loaded instructions file; Cursor and Hermes receive
no note. Files edited by Summon are backed up to `~/.local/state/summon/backups/connect/`; vendor CLI edits
remain the vendor's responsibility. Symlinked dotfiles are edited in place. Summon's JSON/note/hook changes
are idempotent; some CLI targets have no presence-check command and receive `mcp add` again on another run.
`summon disconnect` removes Summon's entry/note/hooks without replacing unrelated configuration; OpenCode's
server removal is manual because its configured CLI method has no remove command.

Claude Code, Codex, Cursor and the Antigravity CLI also get a session-start hook that runs `summon context --hook
<agent>`. It goes in `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.cursor/hooks.json` or
`~/.gemini/config/hooks.json`. Every new session then starts knowing this Mac's state without calling a tool. The hook
prints plain text for Claude Code and Codex, and the JSON shape Cursor and `agy` read. For Claude Code and Codex
the start hook also records the session in Activity, and a `SessionEnd` hook (`summon event hook end --agent <id>`)
closes it. The user's own hooks stay, and
disconnect removes only Summon's. Paths per agent: [research note](research/2026-10-25-agent-mcp-configs.md).

It also serves the resource `mac://context`. Setting ids are checked before they reach macctl, so an id that looks
like an option is refused. Register manually with `claude mcp add --scope user summon -- summon mcp`, or configure
command `summon` and args `["mcp"]` in another client. The optional Claude Code plugin declares no second server.

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
| `mac-app-test` | Test an app before it is done: Core and model tests, the gate, every way in (launch, My Apps, icon, hotkey, reopen) with a window check, logs, screenshots, and a click-through for the user |
| `diagnose-crash-mac` | Why an app crashed, hung or was killed, from its diagnostic report |
| `mac-logs` | Read the unified log, app and launchd logs, install logs |

Commands: `/summon:setup`, `/summon:fix`, `/summon:theme`, `/summon:icon`, `/summon:new-menubar`,
`/summon:new-app`, `/summon:new-cli`, `/summon:new-screensaver`, `/summon:activity`.

Every `summon` command, with arguments and examples: `summon commands --json`.

### ~/Summon: one home

- Summon-managed projects and generated work have one home, `~/Summon`: `Apps/<name>` (template projects),
  `Art/<job>` (wallpaper/icon candidates), `Tasks/<id>` (task-run logs), and `Themes` (a link to installed themes).
  Agents normally start in this home when launched from `~` or `/`; explicit task directories can differ.
  `.gitignore` keeps generated parts out of git. `summon home` initializes it and migrates older Summon files.
- Kept tidy once a day (or `summon clean --apply`, Settings › General › Clean Now…): task logs retain the actual
  newest 20 by modification time and none older than 30 days; removed-task folders wait seven days. Active runs and
  pending recovery logs are protected by a per-task lease, and busy tasks leave automatic cleanup due. Old art jobs
  and Antigravity originals go to the Trash; apps are never touched; unfinished themes are reported.
  `summon clean --json` previews candidates. A partial Trash failure is reported rather than stamped complete.

### Screenshots and the showcase

- `summon project shots <name>`: light and dark pictures in the app's `docs/screenshots/`, a Screenshots section in its
  README, committed; also run by `summon project repo` before the first push. Menu bar apps draw their own panel
  (`--screenshot`); window apps are captured live. CLI tools get their `--help` in the README.
- `summon showcase`: `~/Summon/Showcase/index.html`, every app with its pictures, kind and summary.

### Recurring agent tasks

- Describe it, the agent sets it up: `summon task new "every weekday at 9, check brew updates"` (or Summon Menu ›
  Agent › Schedule a Task…, or "summon, every morning…" in any agent chat). The agent asks what is unclear, writes
  a complete headless-run prompt, and adds the task; its saved execution mode still determines agent controls.
- Directly: `summon task add "<prompt>" --at 09:00 [--weekdays]` or `--every 2h`, optionally `--agent <id>` and
  `--name`, `--execution normal|unattended` and `--directory <path>`; `summon task list`, `summon task run <id>`,
  `summon task remove <id>`. New tasks retain the selected agent, execution mode and directory. Headless support
  currently exists for Claude Code, Codex, OpenCode, Antigravity and Pi, not all ten launchable agents.
- Settings › Tasks shows each task (schedule, agent, last result), view only.
- Each task is a LaunchAgent that runs the agent's print mode in the saved directory (default `~/Summon`),
  after a checkpoint, with a 30-minute deadline. Overlapping runs are refused; failures return nonzero and
  appear in Activity. Bounded private logs live in `~/Summon/Tasks/<id>/`. Deadline/cancellation clean up the
  invocation's process group; deliberately detached processes and completed external effects are excluded.
- Task and Activity results use the same terminal projection; log rotation and equal-timestamp runs retain distinct
  identities. A recovered run is not falsely marked interrupted if its result was already committed.

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
| Appearance | dark mode, scroll bars, menu icons (macOS 26+), accent color |
| Desktop | wallpaper (every screen) |
| Windows | click wallpaper to reveal desktop, tile by edge drag, tile margins |
| Menu bar | menu bar agent and keyboard navigation (macOS 27+, hidden) |
| Documents | save new documents to iCloud, autocorrect |

Agents use it through the workspace skill `MacSetup`.

The following companion-app summaries describe separate projects linked from this workspace, not code shipped
inside SummonOS's universal archive. Their linked repositories/releases own their current behavior and support.

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
| `install.sh` | Release install defaults to the first non-edge release returned by GitHub, including prereleases; checksum-verified; `--channel edge` is opt-in. A checkout or `--from-source` builds source; offers `summon connect`; [agent install guide](install-ai.md) |
| `.github/workflows/release.yml` | Tagged previews and opt-in rolling edge assets: universal commands/app, checksums and attestation. Successful `main` push CI triggers edge publication; a trigger alone does not prove a new asset exists |
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

CI ([`swift.yml`](../.github/workflows/swift.yml)) runs on PRs, pushes to `main` and manual dispatch. New PR
commits cancel older runs; pushes to `main` are not cancelled. [`tools/ci-plan.sh`](../tools/ci-plan.sh) selects
only packages touched by a PR. Summon and macctl run on `macos-15` and `macos-26` with Xcode 26; raw template
packages run on `macos-26` only. A template change also tests Summon, whose tests read the templates. Docs and
workspace-tool changes skip package builds, while unknown files, workflow changes, pushes and manual runs
build everything. Design-skill changes select their example-typecheck job; structural skill, workspace, shell,
privacy and tooling checks run in the workspace job. A selected Summon build also runs the packaged identity
and real Core lifecycle gate; a selected macctl build runs its crash matrix. The optional Xcode 27 preview leg
is informational and skips when unavailable.

[`templates.yml`](../.github/workflows/templates.yml) separately creates projects in a temporary home and runs
their check scripts when template/copier paths change. Its hosted matrix covers **menubar, menubar-panel, app,
cli and screensaver**, not all nine starter kinds; `scripts/check-templates.sh` without arguments covers all nine.
[`codeql.yml`](../.github/workflows/codeql.yml) analyzes Summon/macctl Swift on matching PRs, `main` and weekly;
Dependabot updates SHA-pinned actions weekly. [`release-smoke.yml`](../.github/workflows/release-smoke.yml)
uses the public installer for published/manual releases, but builds and verifies the candidate on matching PRs.
On disposable hosted runners its automated release/PR path also invokes the guarded About/panel runtime audit;
manual dispatch does not run that GUI step. A workflow definition is not proof its runtime gates passed.

[`visual-qa.yml`](../.github/workflows/visual-qa.yml) opens the panel, Settings sections, Activity and sample
crash alert in light/dark on hosted macOS 15/26 runners, uploading 14-day screenshots. It fails on missing or
wrong-theme captures but is not a merge gate and is not full keyboard, VoiceOver or Reduce Transparency acceptance.

The docs bundle can be rendered as a searchable wiki-style site; see [documentation maintenance](documentation.md)
for preview, strict build and deployment prerequisites. Site tooling alone is not proof of a live deployment.
