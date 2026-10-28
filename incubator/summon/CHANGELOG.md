# Changelog

All notable changes to Summon. Newest first. Summon is still incubating in the SummonOS workspace; entries are
grouped by day and point at the pull request. SummonOS releases (one version for `summon`, `macctl` and Summon.app,
see `VERSION`) are on [GitHub Releases](https://github.com/RohiRIK/SummonOS/releases): `v0.1.0` (up to #77) and
`v0.1.1` (#78 to #90), both on 2026-10-25, `v0.2.0` (#91 to #114) on 2026-10-26, `v0.2.1` (#115) and `v0.2.2` (#116). Later changes ship on the rolling `edge` prerelease until the next tag.

## 2026-10-28

### Added

- A failed update row has Fix with AI: your agent gets the command and the end of its output, fixes the cause and
  runs the update again.

### Fixed
- Clicking an Update row did nothing: the rows had no shell action, and the panel ran only rows with one. They
  now install (the panel stays open and shows progress) and search finds them (#115). Released as SummonOS 0.2.1.
- An Updates window replaces the panel's Update folder: every update with its own Update button and live state,
  output on failure, Open in Terminal for a password, Update All per section, What's New and Skip This Version, one
  notification per new set. The old Update Homebrew Apps row, which started a whole agent session just to run
  brew, is gone (#115).
- `ExcUserFault_*` reports (EXC_GUARD user faults: the process kept running) no longer notify; they stay in
  Activity (#115).

## 2026-10-26

### Added
- The app updates itself (#114): it checks at launch and daily, and one click installs with the same verified,
  rolled-back install as `summon update`, then relaunches. The panel's Update folder is back under Make Something
  with Summon, Agents, Homebrew, bun & npm and macOS updates, each tagged "New x.y.z". Crashes became
  notifications instead of a panel row. Released as SummonOS 0.2.0.
- A first-run welcome window: choose the agent, allow Accessibility (live status), then see the menu bar icon and
  ⌃⌥Space; Done opens the panel. Shown once, skipped by closing it, and never on an update that is already set up.
  Settings › General › Show Welcome Again and `summon://welcome` reopen it.
- `summon project new <name> --kind widget`: a desktop and Notification Center widget (a countdown to a date set
  with Edit Widget, small and medium, a live timer on the day) and the one-window app that carries it. Logic and
  views are a Swift package; a small `Xcode/` project builds the app and the sandboxed widget extension, the one
  template with an `.xcodeproj` (owner's decision). Make Something › New Widget.

## 2026-10-25

### Added
- Three new project templates, one per UX surface: `summon project new <name> --kind launcher` (a ⌥Space command
  bar over any app: pre-warmed panel, fuzzy app search, ⌘1–9, ⌘K actions, file drop), `--kind hud` (an
  always-on-top stopwatch pill that never takes focus, thrown to the nearest corner), `--kind notch` (a drop shelf
  that grows out of the camera housing, with a fallback on screens without one). Make Something has a menu item
  for each.
- Templates follow the UX surface rules: every Settings window is close only and 480 pt; the window app has an
  inspector, ⌘F search, context menus and undoable deletes from 800 × 550; `menubar-panel` has a right-click menu
  and "Show in menu bar"; `app` and `menubar-panel` open a first-run welcome window once (Settings shows it again).
- One canonical template set in `templates/{menubar,menubar-panel,app,cli,screensaver}` with a shared kit (menu
  rows, Summon theme, Liquid Glass controls, Open at Login, app icon, `--screenshot`); `examples/` is gone and
  `tools/mp new --kind <kind>` copies these templates. Every template has a `scripts/test.sh` (#95).
- `summon agents install` / `summon agents update [--check]`: install coding agents with bun (npm agents) or the
  vendor script, and update each the way it was installed (brew, cask, bun, npm, vendor updater) (#94).
- `summon update [--channel stable|edge] [--check] [--yes]`, and a rolling `edge` prerelease built after every green
  `main`; `install.sh --channel edge` installs it, never by default (#89).
- Visual QA screenshots every Settings page, Activity and the crash alert; `summon://settings/<section>` opens a
  Settings page (#91).
- CI: CodeQL for Swift, a privacy scan, Dependabot for pinned actions, and a post-release smoke test (#88).
- SummonOS 0.1.1 (#78 to #90): undo any agent's session (MCP checkpoints, one "Undo <Agent> Session" row), the agent
  hotkey starts the agent with what is on screen, Accessibility in one click, `summon connect` session hooks
  record Claude Code and Codex sessions in Activity, `summon theme set` themes the whole Mac (accent, VS
  Code/Cursor, Neovim) with one undo, checkpoint undo removes the files a theme created, live Mac events (`mac.*`,
  `summon events --follow`, MCP tool `mac_events`).
- SummonOS 0.1.0 (#72 to #77): `summon context` (one snapshot of this Mac for agents), `summon mcp` (an MCP server
  with 10 tools), `summon connect` / `disconnect` for every installed agent, session-start hooks, one `VERSION` with
  `summon --version` and `macctl --version`, and the release workflow with checksum-verified binary installs.

### Changed
- Minimal panel: Needs attention, Now, Recent and three actions; the rest by search or Settings › Setup; Liquid
  Glass, 320 pt; no agent clock in the menu bar by default (#96).
- UX quick wins: Needs attention in the panel with an agent picker, one Settings window without header blocks,
  undo asks "Restore N Changes" with Cancel as the default, orange menu bar icon for problems (#93).
- `summon default repos` defaults to `ask`: no GitHub repo until `summon project repo` and its dialog; a saved
  `always` is kept. The `mac-app` skill is exact steps (#92).

### Fixed
- Settings: only the close button works (minimize and zoom dimmed, no full screen, per the HIG), and the window is
  780–820 pt wide instead of 860 or more.
- The crash alert stays out of Mission Control, ⌘` and the Window menu.
- VoiceOver reads a menu entry's health badge; the dot was color only.
- `docs/ux-audit.md`: every Summon surface checked against the UX surface table.

## 2026-10-24

### Added
- Every prompt Summon gives an agent ends with a `## Summon session` block: working folder, checkpoint id and undo
  command, approval mode, skill files; scheduled runs are also told nobody is watching and to end with a summary.
- Settings › Notifications: show crashes as a Summon alert or a macOS banner, task result notifications, sound.
- Task results are posted by Summon.app with Show Log and Ask Agent (a plain banner only when the app is not running).
- The menu bar icon shows a running agent's elapsed time (`mm:ss`, monospaced) with the panel closed; Settings ›
  General › Menu Bar turns it off. Its VoiceOver label names the agent and how long it has run.
- Opening the panel with ⌃⌥Space or a `summon://` URL is announced to VoiceOver.

### Fixed
- The crash alert took keyboard focus, so Return typed into another app could start Diagnose; it now appears
  without focus. Each crash no longer shows both a banner and the alert; a burst shows one alert, banners group.
- Banner sound never played (no sound was set on the content).
- Prompts: Fix with AI lists failures first and asks before risky steps; item-health and Activity prompts mark logs
  as evidence; the crashed-app prompt and `diagnose-crash-mac` agree that the user's own apps may be fixed.
- Skills: `summon-mac` no longer names the owner, describes both approval modes, and has the right task log
  folder (`~/Summon/Tasks/<id>`); undo commands are the same in every skill.

## 2026-10-22

### Added
- **`summon-migrate` Skill & Project Import Commands:**
  - Added new `summon-migrate` skill to guide migrating external Mac apps and legacy plugins into `~/Summon/Apps/<name>`.
  - Added `summon project import <path>` to copy and register external apps, auto-detecting app kind and Git remotes.
  - Added `summon project register <name>` to register existing folders in `~/Summon/Apps/`.
  - Migrated `mac-network`, `mac-calendar`, and `mac-breathe` into first-class Summon apps in `~/Summon/Apps/`.
- **Health Engine & "Fix with AI" for Apps, Themes, and Art:**
  - `ItemHealth` engine automatically audits every app project, theme, and art job in real time.
  - Per-item "Fix with AI" triggers dispatch targeted prompts directly to the user's default agent using `summon-art`, `summon-mac`, or `diagnose-crash-mac` skills.
  - Comprehensive art inspection checks App Icons (`Resources/AppIcon.icns`), UI screenshots (`docs/screenshots/`), theme wallpapers (`~/.config/summon/themes/<slug>/`), and `~/Summon/Art` jobs.
  - Added `summon fix` CLI command and interactive "Fix with AI" button in Settings › General diagnostics.
- **My Apps in Settings:**
  - Dedicated "My Apps" section in Settings with panel-matching drill-down navigation (Panel Apps, Window Apps, Themes, Art & Wallpapers, CLI Tools, Screensavers).
  - Shows live health badges, status summaries, open in Finder/GitHub shortcuts, and instant theme preview dots.
- **Active Theme Pill in Panel:**
  - Header displays a pill badge with the name of the currently active theme alongside the Summon title.

### Fixed
- **Panel Back Navigation:**
  - Replaced static chevron image with an interactive, hover-highlighted Back button in the panel search bar.
  - `Escape` key inside submenus pops back to parent level instead of abruptly dismissing the panel.
  - `Delete` / Backspace on empty search query navigates up one level.
  - Robust dotted-ID popping prevents getting stuck in nested levels.
- **Dedicated Windows for Settings and Activity:**
  - Settings and Activity now open in standalone foreground `NSWindow`s centered on the active display, avoiding panel focus theft or background placement.
- **Binary Precedence for Agent Tool Locators (#67):**
  - User-installed binary directories (`~/.bun/bin`, `~/.local/bin`, `~/.cargo/bin`) strictly precede `/opt/homebrew/bin`, fixing conflicts where outdated Homebrew agent binaries (e.g., OpenCode 1.15) were invoked instead of modern Bun tools.
- **Process Buffer & Checkpoint Protection:**
  - Expanded child process execution output buffer from 1MB to 16MB.
  - Sanitized and truncated checkpoint problem records to 2,000 characters to prevent checkpoint store bloat.

## 2026-10-21

### Added
- **Command-Return / Option-Return Panel Agent Quick-Launch (#65):**
  - Option-Enter / Command-Return from the menu bar panel opens the user's default agent in terminal directly from `~/Summon`.
  - Added "My Apps" section organized by template categories to the menu bar tree.
- **Theme Preview with Wallpaper and Undo (#66):**
  - Settings › Appearance renders live 16:9 theme wallpaper previews with an Undo button to revert to the previous theme.
  - Added one-click auto-installers for Ghostty and kitty terminals via Homebrew.
- **Visual QA CI (#64):**
  - Automated visual screenshot testing on macOS 26 and 15 runners.

## 2026-10-20

### Menu bar panel (draft)
- `MenuBarExtra` is replaced by an `NSStatusItem` + nonactivating `StatusPanel`, owned by one `PanelController`.
  The panel takes typing without activating Summon.
- The launcher is merged into the panel: its search field and menu tree are now at the top, the launcher window is
  gone, and ⌃⌥Space and `summon://menu/<id>` open the panel.
- Left click opens it. Right click shows Settings…/Quit Summon, which the footer also keeps.
- It opens from `summon panel [--close]` and `open -g summon://panel[/close]`. These URL/CLI opens don't focus the
  search field, and Return is ignored for 300 ms after any hotkey or URL/CLI open, so stray typing can't run an
  entry. A `summon://` URL that launches Summon is queued until the panel exists instead of being dropped.
- It refreshes every second while open, and the agent row shows elapsed mm:ss.
- It closes only on spec section D triggers, including D12: the crash alert closes the panel first, then takes key.
  Every close logs the active monitor count, and the B1 open is an `os_signpost` interval plus a log line measured
  from mouse-down (≤ 200 ms warm). Both use the `local.macplugins.summon` / `panel` Logger.
- The crash alert also uses `.statusBar`. Settings marks shortcuts another app owns.
- `PanelFixture=tall` is a debug-only fixture; build one with `scripts/bundle.sh --debug`. See `docs/menubar-panel.md`. `WindowTopPinner` and `LauncherView` are gone.

### Security and recovery
- Validate theme text and wallpaper containment; preserve foreign skill links and record owned links.
- Persist checkpoint capture failures without advertising a stale Git commit; scheduled work stops on capture failure.
- Use bounded/cancellable process groups, hard deadlines, bounded private logs and nonzero failed-task status.
- Preserve corrupt task/agent state; serialize task scheduling and Activity writes; drain crash bursts without the five-report loss.
- Add Agent controls / Unattended execution preference, preserving existing choices and freezing new task bindings.
- Redact known diagnostic identifiers/credential labels before export; redaction still needs human review.
- Stage installations with rollback, record ownership for uninstall, and support exact-source releases and optional notarization.
- Exclude the development crash-test URL route from release builds.

## 2026-10-19

### Added
- **Every new app gets a private GitHub repo.** `summon project new` creates it right away (screenshots, CI, first
  push) under a standing approval: Settings › General › "Create a private GitHub repo for every new app" (on by
  default; `summon default repos always|ask`). With it off, Summon's dialog asks each time. Repos are always private.
  If gh is missing or not logged in, the app is still made and Summon says how to finish (`summon project repo`).
  The mac-app skill and the `/summon:new-*` commands now tell agents to make sure the repo exists.
- **Screenshots of every app, and a showcase.** `summon project shots <name>` builds the app and saves light and dark
  pictures to `docs/screenshots/`, adds a Screenshots section to its README and commits; `summon project repo` runs it
  before the first push. Menu bar apps from the template draw their own panel off-screen (`<App> --screenshot`), so it
  works even when the menu bar is full; window apps are captured live with ScreenCaptureKit. `summon showcase` writes
  `~/Summon/Showcase/index.html`, a gallery of every app (light and dark).
- **Keeping ~/Summon tidy.** Once a day (and with Settings › General › Clean Now…, or `summon clean --apply`) old
  Summon files go to the macOS Trash: task logs beyond the newest 20 or older than 30 days, a removed task's folder
  after 7 days, art jobs untouched for 30 days, Antigravity originals after 14. Apps are never touched; unknown apps,
  themes without a wallpaper and broken theme files are reported. `summon clean` alone previews.
- `summon theme check <slug>` says why a theme does not appear in `theme list`.
- **Plugins in Settings › Agents.** Each agent's installed plugins (Codex: its MCP servers) and Add, which runs the
  agent's own installer (OpenCode: added to `opencode.json`, backup kept). **Shared plugins**: Summon's catalog,
  starting with OpenLTM, installs the right build into every agent (Install in All) and hands a broken one to your
  agent (Fix…). CLI: `summon agents plugins|plugin-add`, `summon plugins [install|fix]`.
- **Recent Problems archive themselves.** The panel shows a report for 24 hours; Diagnose… archives that app's
  reports; Clear archives the rest. Activity keeps the full history.
- **Settings › Agents knows each agent's account and models.** It asks the agent's own CLI: logged in or not (with
  Log In…, which opens that agent's login in a terminal), and the real model list as suggestions in the Model field
  (Antigravity 13, Pi ~470; Claude Code's aliases). Each skill shows its description. CLI: `summon agents status
  <agent> [--json]`, `summon agents login <agent>`, `summon skills list --json`.
- **Tasks by conversation.** `summon task new "<what you want>"` (or Agent › Schedule a Task…, or "summon, every
  morning…" in a chat) opens the agent, which asks what is unclear, writes the run prompt and adds the task.
- Local CI: `tools/local-ci.sh <pr>` builds and tests every package on the Mac and posts the result on the commit.
- `summon doctor` checks recurring tasks: each needs its LaunchAgent and an agent that can run unattended (from #40).
- **Recurring agent tasks.** `summon task add "<prompt>" --at 09:00 [--weekdays]` or `--every 2h`, with
  `list`, `run` and `remove`, plus a Tasks tab in Settings. Each task is a LaunchAgent that runs the agent
  unattended after a checkpoint, logs every run, and reports in Activity and a notification. (#41)
- `summon://settings` opens the Settings window. (#35)

### Changed
- **`~/Summon` is the one home for everything Summon and its agents make**: `Apps/` (apps from the templates),
  `Art/` (wallpaper and icon jobs, every candidate), `Tasks/` (recurring task results), and `Themes` (a link to
  `~/.config/summon/themes`). A `.gitignore` keeps the generated parts out of git. `summon home` (also run at
  install and on every launch) sets it up and moved older files in: art from `~/Downloads/summon-art` and
  `~/Downloads/summon-wallpapers`, task logs from `~/.local/state/summon/tasks`, apps from `~/Summon/<name>`.
  The art skill now generates into `~/Summon/Art/<job>/`.
- **Settings › Agents redesigned** (after Hermes's settings, lean): the agents on the left with a status dot and
  Default, **All Agents** on top (default agent, where agents open, the skills every agent gets, shared plugins),
  and the same sections for every agent: Account, Model (picked from that agent's list, or Custom…), Skills
  ("Same as All Agents" or Custom, with Use All Agents), Plugins (installed, OpenLTM as a recommended Install /
  Fix…, Add). The Terminal tab moved into All Agents. CLI: `summon agents defaults [--skills a,b | --all-skills]`.
- Settings uses toolbar tabs (General, Agents, Terminal, Notifications, Appearance, Tasks) instead of a
  sidebar. Short tabs fit their rows; the `summon` router skill cannot be switched off for an agent. (#35)
- Settings › Tasks is view only (schedule, agent, last result); tasks are made by describing them to the agent.

### Fixed
- `summon project shots` hung on an app made before the template's `--screenshot` mode (it launched and never
  exited); that call now stops after 20 seconds and falls back.
- **Agent-made themes were silently skipped.** The art skill said "work in OKLCH" but not that `theme.json` must
  hold `#RRGGBB`; agents wrote `oklch(…)` and `//` comments, and their palettes had an accent darker than the
  background and sixteen shades of one blue. Theme files now accept `oklch(L C H)` (converted to hex for every app);
  `summon theme check` also checks contrast and that the terminal's red is red, and the skill shows a complete file
  and requires a clean check before `theme set`. Hearts Valley and Prance Coffee were rebuilt and now appear.
- Summon Dawn's bright cyan was 2.3:1 on its background; now #0077A3 (4.6:1).
- Low-memory (Jetsam, bug_type 298) reports showed as a "Hang" named after the file (hangs are bug_type 288). They
  now name the process macOS stopped and why ("knowledgeconstructiond · Stopped · over its own memory limit"), not
  the biggest bystander; routine kills (over its own cap, idle) are listed but not announced.
- Clicking a Recent Problems row runs Diagnose, like its button.
- Summon found an old Homebrew OpenCode (1.15) before your bun one (2.0); your own folders now come first, as in
  your shell.
- Ask Agent with Pi (or any `#!/usr/bin/env node` agent) failed in Ghostty with `env: node: No such file or
  directory`: Ghostty starts commands with a bare PATH. Agents now run through your login shell
  (`zsh -lic 'exec "$@"' …`), so they get the PATH your terminal has; `~/.bun/bin` is searched too.
- `summon project repo`: the private-repo approval dialog closed itself after ~2 s; it now stays open until answered. (#43)
- `summon://activity` (and the new `summon://settings`) never opened anything: the opener sat on the menu
  bar icon, which macOS draws as an image. It now lives in an invisible window. (#35)

## 2026-10-18

### Added
- **`summon` router skill.** Say "summon, build a web app" to any agent: the skill picks the right one of
  `summon-mac`, `summon-art`, `mac-app`, `diagnose-crash-mac`, `mac-logs`, or the agent's own skills. (#32)
- **Per-agent model and skills.** `summon agents set <agent> --model … --skills …`, saved in
  `~/.config/summon/agents.json`, and editable in Settings › Agents. (#33)
- **Skills in every agent.** `summon skills link` links Summon's skills into each agent's own folder
  (Claude Code, Codex, OpenCode, Antigravity, Pi); it runs on install and on every app launch. Prompts
  also carry the skill file paths for agents without a skill mechanism. (#29)
- **`summon-art` skill:** themes, wallpapers and icons that are art-directed (mood, three concepts, a palette
  with a contrast check, Nano Banana images, review before you see them). (#30)
- **Pi** as an agent. (#31)
- **kitty** as a terminal (`summon default terminal`, Settings › Terminal, Install › kitty, `kitty.conf` from
  every theme); muted apps with Unmute in Settings. (#27)
- Activity window as a simple log: one line per event, oldest first; select lines and ask the agent about
  them; right-click to copy, diagnose or undo. (#28)
- `summon doctor`: checks the install, config, agents, skills, macctl and project templates. (#36, #39)
- Projects from templates in `~/Summon` (menu bar app, window app, CLI tool, screensaver). (#37)

### Changed
- Agents launch with permission prompts bypassed (Claude Code `--dangerously-skip-permissions`, Codex
  `--dangerously-bypass-approvals-and-sandbox`), always behind a checkpoint. (#26)
- Leaner menu bar panel (actions, and problems only when there are some) and a short Settings window. (#26)
- The previous `summon` skill (Mac customization) is now `summon-mac`. (#32)

### Fixed
- One agent launch opened a second Ghostty app; it now opens one new window in the running Ghostty. (#26)
- The crash prompt pointed agents at a skill file that did not exist. (#29)

## 2026-10-17 and earlier

- Where it started: **mac-assistant** (2026-10-03), a diagnostics assistant with a policy broker and typed tools.
  Archived at the tag `archive/mac-assistant`.

- The `summon` CLI and the Summon Menu app (#13), the Activity event log, timeline and window (#22, #23),
  Claude Code plugin session hooks (#24), themes, wallpapers, the logo and desktop configs (#12), and theme
  wallpapers through `macctl` so undo restores them (#18).
