# Project Context

## Overview
Summon is Rohi's agent layer for macOS: one default coding agent summoned from anywhere
(hotkey, drop-down terminal, menu bar, Summon Menu, notifications), the Mac handing it crashes and failures,
skills linked into every agent CLI, one theme across macOS, terminal, tiling, borders and agents, and a
checkpoint before every agent session. It started from research on Omarchy 4.0; it is designed as its own thing.

## Current State
- Incubating at `incubator/summon/` in the SummonOS workspace (`RohiRIK/SummonOS`). Target repos: `mac-summon-dev` / `mac-summon`.
- `plugin/`: Claude Code plugin (7 skills, 9 commands, declares the `summon mcp` server). `themes/`: 9 theme.json + wallpapers.
  `config/`: Brewfile, AeroSpace, Ghostty, borders, zsh. `design/`: brand assets + `generate.py`.
- Swift package: `SummonCore` (agents, launch plans, .ips crash parsing + watcher, menu tree, themes + compilers,
  checkpoints, debug bundle, hooks, command catalog), `summon` CLI, `SummonMenuUI` + `SummonMenu` app (menu bar panel
  (⌃⌥Space) with the Summon Menu, ⌃⌥⌘A agent, crash notifications, Activity window, Settings).
  Since PR #61 (draft): the menu bar panel is an `NSStatusItem` + nonactivating `StatusPanel` (`PanelController`), with
  the Summon Menu (former launcher) inside it. It opens with ⌃⌥Space, `summon panel [--close]`, `open -g summon://panel`
  and `summon://menu/<id>`; there's no launcher window. Spec and proof hooks: `docs/menubar-panel.md`.
  Debug build for the E4 fixture: `scripts/bundle.sh --debug`. Builds on CI; installed and used on Rohi's Mac 2026-10-18.
- Projects: `templates/{menubar,menubar-panel,app,cli,screensaver}`, the workspace's only templates (`tools/mp new`
  copies them too, with `local.macplugins.`). Each is a buildable package with README, MIT LICENSE,
  PROJECT-CONTEXT.md, `scripts/check.sh` + `scripts/test.sh` (CLT-compatible); UI kinds share Components, SummonTheme
  (`.themed()`), Glass (`.glassControl()`), Screenshots (`--screenshot`), Open at Login, `Resources/AppIcon.icns`.
  `--kind` is a `ProjectStarter` (template folder); the registry keeps the `ProjectKind` (`menubar-panel` → `menubar`).
  CI job `templates` runs `summon project new` for every kind in a temp HOME and each one's `scripts/check.sh`.
  `summon project new` copies one to `~/Summon/Apps/<name>` and records it in the private
  `~/.config/summon/projects.json`; `summon project repo` makes a private repo after a native dialog. Core:
  `Projects.swift`. Bundled into `Contents/share/summon/templates`.
- Bundle id `local.macplugins.summon`. Depends on `macctl` (`macctl/` in the workspace) for every settings change.

## Constraints
- Original design: Omarchy and other projects are research, not a spec to port (Rohi, 2026-10-18).
- Existing configured installs retain unattended execution; new installs use harness controls until unattended
  is selected (approved hardening, 2026-10-20). Checkpoints cover supported settings/captured config only,
  and do not sandbox agents.
- Third-party tools via Homebrew are allowed (AeroSpace, Ghostty, JankyBorders) (Rohi, 2026-10-17).
- Shape: Claude Code plugin + native Summon Menu app (Rohi, 2026-10-17). Name chosen by Rohi: Summon.
- Settings go through `macctl`; no passwordless sudo (Touch ID for sudo instead).
- Panel vs Settings window split from AGENTS.md applies to the Summon Menu app.
- Projects live in `~/Summon/Apps/<name>` (created on install, app launch and agent launch; agents start there). The
  project list is private to the Mac: never `plugins.json`, never `tools/mp new/promote` (Rohi, 2026-10-18).
- GitHub: only a private repo, ever. Default `ask` (no saved `~/.config/summon/defaults/repos`): a new app gets no
  repo until `summon project repo`, approved in the dialog (Cancel default). With the owner's standing approval
  (Settings › General, `always`, kept when already saved) `summon project new` creates it right away (Rohi,
  2026-10-25, replacing the 2026-10-19 `always` default). CI is added with the repo. Public publishing is a separate choice
  through the workspace's `tools/publish-public.sh` (Rohi, 2026-10-18; standing approval 2026-10-19).

## Recent History
### 2026-10-28 — Updates window (0.2.1)
- Owner asked for a much better update UX: `UpdatesView` (App Store style, sections per `SoftwareUpdate.Group`, per-row
  `UpdateRowState`, one install at a time, Open in Terminal only for password failures). The panel only has the Update
  row and the tag; both open the window (`MenuTree.runsInApp("update")`). Prefs: `UpdatePreferencesStore`.
- `SummonMenu --screenshot <dir>` renders the Updates window (sample data) light/dark: look at UI changes without
  Screen Recording. User faults (`ExcUserFault_*`) are routine: no notification.
### 2026-10-26 — The app updates itself (check + one click)
- Summon.app checks the remembered channel at launch, then daily (`defaults/update-check`, on by default). A newer
  build shows a panel row "Summon X available · Update"; Settings › General › Updates has the toggle, the channel
  and Check Now. Install = `summon update`'s verified, rolled-back install, then a relaunch with `--updated`, which
  asks for Accessibility again (ad-hoc builds lose it on every update). Owner chose one click over silent installs.
- Owner follow-up: one Updates folder under Make Something for Summon + Homebrew + bun + npm + macOS
  (`SoftwareUpdates.swift`), a count tag top right of the panel. Crashes left the panel (no row; alert style
  defaults to the macOS notification); Needs attention is setup problems only.
- The anonymous GitHub API returns 403 behind the owner's VPN; `check` falls back to a logged-in `gh api`.
### 2026-10-26 — Panel polish (owner rejected Now + Recent)
- Header shows the Summon mark (app icon) instead of a stock sparkle; "Search Summon…" is always visible; panel text
  uses body / headline / subheadline only. A Now + Recent layout was built and rejected by the owner (recent logs and
  a NOW section felt weird): do not add activity rows to the panel.

### 2026-10-26 — Welcome window polish (U4, docs/ux-surfaces/06-onboarding.md)
- Four steps, 720 × 480: `welcome` (new: `banner.png` header bundled into Resources by bundle.sh, three feature
  rows), agent rows with `AgentBrandIcon` + live login (`checkAgent`, re-checked every 5 s while logged out),
  Accessibility (footer "Skip" while off, visible re-grant hint), ready ("Try it now" ticks green when
  `PanelState.session` moves; warns when `PanelController.isStatusItemVisible` is false).
- `SummonModel.preview()` now has three installed agents with login states. Pages checked by rendering each with
  `ImageRenderer` (ScrollView contents don't render there; rows rendered alone).

### 2026-10-26 — Tool search follows PATH order
- `ToolLocator.live`: PATH order wins among its own folders; user folders missing from PATH go before the first
  system folder (GUI app keeps user folders before Homebrew). Added `~/.opencode/bin`. Found on a real Mac where
  Summon picked a broken bun OpenCode over the vendor copy the shell runs.
- First full local run on Xcode 27.1: 335 + 150 tests green; panel, 8 Settings pages, Activity, Welcome open; CLI
  read-only commands exit 0.

### 2026-10-26 — First-run welcome window
- `OnboardingView` (Window scene `onboarding`, 640 × 440, close only via `closeOnlyWindow()`): agent, Accessibility,
  ready. `OnboardingFlow.launch` (Core, tested) decides at launch in `ActivityOpener`; key
  `summon.onboarding.completed`; skipped when `VisualQA` is set. Reopened by Settings › General and `summon://welcome`.
### 2026-10-25 — Existing templates brought to the surface rules
- Kit: `CloseOnlyWindow.swift` (`.closeOnlyWindow()`, the probe Summon's Settings uses) in all six UI templates;
  `OnboardingFlow` (Core) + `Onboarding.swift` (window, permission cards, `showsOnboardingOnFirstLaunch()`,
  `ShowWelcomeButton`) in `app` and `menubar-panel`. Starter permissions list is empty on purpose (HIG Privacy).
- `app`: 800 × 550 min, `.inspector`, `.searchable` + ⌘F, context menu, undo via the window's UndoManager.
- `menubar-panel`: right-click menu on the status item, `isStatusItemVisible`, reopen shows Settings. `menubar`
  (MenuBarExtra) has no hide toggle: it has no way back once hidden.
### 2026-10-26 — Widget template
- New template `widget` (ProjectStarter case, recorded as `.app`), the owner's choice of "Xcode project for the
  widget only": root `Package.swift` (Core + UI, product `StarterKit`) plus `Xcode/Starter.xcodeproj` (objectVersion
  77, synchronized folders, local package `..`, ad hoc signing, sandboxed extension). `scripts/bundle.sh` uses
  xcodebuild. No App Group (ad hoc signing); configuration is Edit Widget (`AppIntentConfiguration`).
- swift.yml builds the package only; the Xcode build runs in `scripts/check.sh`, so only `templates.yml` (matrix
  still owner-only) or a Mac covers it. Not built with Xcode or run on a Mac yet.
### 2026-10-25 — Templates for the UX surfaces
- New templates `launcher`, `hud`, `notch` (ProjectStarter cases, all recorded as `.menubar`), built to
  `docs/ux-surfaces/04`, `05` and `07`. They share a small kit: `KeyCombo` (Core, refuses ⌘Space and other system
  shortcuts), `HotKey` (Carbon `RegisterEventHotKey`), `ShortcutRecorder`, `ActionMenu`/`StatusMenu` (a hideable
  menu bar menu), `SettingsOpener`. Settings windows in them dim minimize (`windowMinimizeBehavior(.disabled)`).
- `templates.yml` can't be edited from a Claude session: its matrix still lists only the first five kinds;
  swift.yml builds and tests the three new templates as packages, and `scripts/check-templates.sh` covers all eight.
- Not run on a Mac yet: the HUD focus combination, the launcher over full-screen apps, notch geometry on real
  hardware, hover in an inactive app.
### 2026-10-25 — UX surface audit
- `docs/ux-audit.md` checks every surface against `docs/ux-surfaces/` (table + research). Fixed: Settings close-only
  chrome (`SettingsWindowChrome`) and 780–820 pt width; crash alert `.transient`/`.ignoresCycle`; health dot read
  by VoiceOver. Open: onboarding (owner's call), "Show in menu bar" / removable status item, low-priority extras.
- Mac checks 8–10 added to `docs/menubar-panel.md`.
### 2026-10-25 — One canonical template set
- `examples/menubar-starter` deleted, `examples/menubar-panel-starter` moved in as `templates/menubar-panel`;
  `tools/mp new --kind menubar|menubar-panel|app|cli|screensaver` copies `templates/<kind>` (no more silent fallback).
- New `ProjectStarter` (5 templates) over `ProjectKind` (4 registry kinds), so SummonMenuUI's switches stay as they are.
- Template kit (see Current State). Panels follow MenuPanel.md: 300 wide, 6 padding, one command per row, footer
  rows `Settings…` (⌘,, dismisses first) and `Quit <App>` (⌘Q) with key hints. Settings comment states the rule:
  grouped Form under 3 sections, NavigationSplitView sidebar from 3.
- `summon project shots` asks window apps for `--screenshot` too (`window-light/dark.png`); ItemHealth skips the icon
  and screenshot checks for `cli`. UI templates do not compile with Command Line Tools only (`@State`, `#Preview`
  macros): CI is their gate; cli and screensaver pass `scripts/check.sh` locally.
### 2026-10-25 — U2 panel v3 (owner: "too messy")
- After seeing "Now + Recent" on the Mac the owner asked for less: home is Ask Agent, Make Something, My Apps, one
  status line (`PanelAttention.summary`; helpers and test runners filtered by `isHelper`), undo, Activity…,
  Settings…, Quit. The search field is hidden at home (height 0) and appears with the first typed letter. Now and Recent
  were removed. The header shows "running 3h" (coarse `PanelClock.ago`).
### 2026-10-25 — U2 minimal panel (first version, "Now + Recent")
- Home (`isHome`: root level, empty query): Needs attention, Now (running session from `activity.status`), Recent
  (`activity.events.prefix(3)`, `PanelClock.ago`), Ask Agent, then only `PanelLayout.homeItems` (make, apps) from the
  tree. Search and submenus still cover the whole Summon Menu. `PanelLayout.setupGroups` render in the new
  Settings › Setup page (`SetupSettings`, Run per action).
- `PanelBackground`: `NSGlassEffectView` on macOS 26, `.menu` material before; no hand-drawn stroke. Width 360 → 320
  (Visual QA `PANEL_W` too). The header no longer shows the running clock (Now does). `menuBarShowsAgentTime`
  defaults to false; `repoPolicy` starts at `.ask` (T2 leftover).
### 2026-10-25 — Agent installer and updater
- Core `AgentInstall.swift`: per-agent `AgentInstall` (npm package, vendor script, verified self-update),
  `DetectedInstall.detect` (Caskroom, Cellar, ~/.bun, node_modules/nvm/fnm/volta, home folder = vendor),
  `AgentInstallPlan` (install/update steps, never sudo), `AgentVersion`, and `AgentUpdates` (check with a 24 h
  cache in `~/.local/state/summon/agent-updates.json`, `cachedUpdateCount`, `markUpdated`). Tested with fakes.
- CLI `summon agents install <agent> [--yes]` and `summon agents update [<agent>|--all] [--check] [--refresh]
  [--yes] [--json]`; `summon agents` shows the method. bun installs pass `--trust`: without it bun skips
  postinstall and opencode-ai's binary is missing. Grok's install hint is now xAI's script.
- The app still has no UI for it; the main thread wires `AgentUpdates` into Settings later.
### 2026-10-25 — Repos default to ask; mac-app skill as exact steps
- `RepoPolicyStore.load()` falls back to `ask`, so an agent's `summon project new` no longer pushes a repo on an
  install that never chose; a saved `always` stays. Catalog and `summon default repos` wording follow; test updated.
- `plugin/skills/mac-app/SKILL.md` rewritten as 8 verified steps (name/kind/repo check, `project new` + `project
  path`, Core test first, `scripts/check.sh`, bundle + `pgrep` + `log show`, `project shots` checklist, icon,
  PROJECT-CONTEXT + optional repo). Theme path fixed (`current-theme` slug + `themes/<slug>/theme.json`; there is no
  `current/theme.json`); `~/Summon/<name>` corrected to `~/Summon/Apps/<name>` in docs; `new-*.md` commands aligned.
### 2026-10-25 — summon update and the edge channel
- `Updater` (Core, tested with a fake curl/ditto runner): `pick` reads the GitHub releases JSON (stable: highest
  `vX.Y.Z` tag, drafts and `edge` skipped; edge: version from the `edge` release's zip name), `ReleaseVersion` is
  SemVer precedence (`0.1.0-edge.x < 0.1.0`), stable updates only forward and edge on any difference. `install`
  downloads zip + `SHA256SUMS`, verifies with CryptoKit, unpacks, checks the layout, then runs the zip's
  `scripts/install.sh` with `SUMMONOS_APP_SOURCE`/`SUMMONOS_MACCTL_SOURCE` (via `/usr/bin/env`), as `install.sh` does.
- `summon update` (CLI): the channel lives in `~/.config/summon/defaults/channel`; prompts on a TTY unless `--yes`;
  runs the new binary's `summon doctor` after. `Shell.live(timeout:)` gives downloads 15 minutes.
- release.yml: `workflow_run` of "Swift (macOS)" (success, push, main, this repo) builds the head commit with
  `Version.swift` stamped `<VERSION>-edge.<sha7>` and replaces the `edge` prerelease's assets (tag moved via the API).
- No Settings › General "Check for Updates…" yet: it needs an async check, a result and an install flow in the app.
### 2026-10-25 — U1 UX quick wins (Phase 5)
- One Settings window: the `Settings` scene only (the duplicate `Window("Summon Settings")` is gone); `ActivityOpener`
  calls `openSettings()` and finds the window by its identifier (its title is the page name now).
- Settings: `detailHeader` removed (`.navigationTitle` per page); General lost the diagnostics card, the
  explanatory subtitles and footer, the "caffeine" line and the second Quit.
- Panel: `PanelAttention` (Core, tested) feeds Needs attention rows (crashes by program → Diagnose…, setup problems →
  Fix…). `checkHealth()` runs at launch and every 10 min in the watch loop. "Choose an agent" menu when no default
  agent, auto-pick when one is installed; the theme chip is gone.
- Undo alert: "Restore N Changes", Cancel default, copy matches #85. The menu bar icon is tinted orange while there is attention.
### 2026-10-25 — Live Mac events for agents
- `MacEvents.changes(from:to:)` (Core, tested) logs only threshold crossings as `mac.network|disk|battery|thermal|display`.
  `SummonModel.checkMac()` runs in the 30 s crash-watch loop (a shortcut, noted in the code: poll rather than
  SCDynamicStore). There is a new `ActivityEvent.Category.mac` (Activity icon `desktopcomputer`, teal).
- `summon events --follow` reloads the timeline every 2 s and prints new events. MCP `mac_events` returns the
  newest `mac.*` log entries (11 tools).
### 2026-10-25 — Undo removes what a change created
- `CreatedFiles` (Core, tested): `theme set` records the files and folders it created as the `created` ref of its
  `theme.set` event (`createdCandidates`, every file listed one by one). `checkpoint undo` removes them deepest
  first, only inside home. A folder goes only when everything left in it is recorded, so files the user added keep it.
  The first version removed a created folder along with a file the user had put in it; the test caught it.
### 2026-10-25 — Theme the whole Mac with one undo
- `ThemeCompiler.accentIndex` (hue → macOS accent, graphite when gray), `vscodeTheme`/`vscodePackage`
  (extension `summon.summon-theme-0.0.1` in `~/.vscode/extensions` and `~/.cursor/extensions` when those exist),
  `nvim` (`~/.config/nvim/colors/summon.lua` when `nvim` is on PATH). macctl gained `appearance.accent-color`
  (`AppleAccentColor`, -1…6, unset = multicolor).
- `summon theme set` creates a checkpoint "Theme <name>" first and logs `theme.set` with `checkpoint` and
  `agent: "Theme <name>"` refs. `UndoOffer` now has a `label` ("Codex Session", "Theme Tokyo Night").
### 2026-10-25 — First real Mac run of the hotkey capture
- Verified on the owner's Mac: ⌃⌥⌘A over Helium sent app, window title, page and selected text. `summon connect
  claude` added the MCP server (✔ Connected), start/end hooks and the note; doctor `plugin` passes.
- Gotcha: ad-hoc preview builds get a new code hash each time, so a stale Accessibility entry looks on but does not
  count (`tccutil reset Accessibility local.macplugins.summon` clears it). The row now polls every 2 s while off
  and, after Allow…, says to turn the switch off and on.
### 2026-10-25 — `summon connect` replaces the plugin's jobs (found on the owner's Mac)
- Claude Code/Codex hooks: `context --hook <id>` also logs `session.start` from the stdin payload, and a new
  `SessionEnd` hook runs `event hook end --agent <id>` (`event hook` takes `--agent`). Activity shows the
  sessions without the plugin.
- `plugin.json` dropped `mcpServers`: with `summon connect` too, Claude would see two `summon` servers.
- Doctor `plugin` check passes when `~/.claude/settings.json` has Summon's start hook. Its fix is now
  `summon connect claude` (the old `--plugin-dir <repo>` fix was useless for release installs).
- `summon fix` sends only `ProblemArchive.visible` crashes (24 h, not archived) and archives what it sent.
### 2026-10-25 — Accessibility in one click; skills only for installed agents
- Settings › General › Permissions: `requestAccessibility()` calls `AXIsProcessTrustedWithOptions` with the prompt
  key, written as the string "AXTrustedCheckOptionPrompt" because the global is not concurrency-safe in Swift 6. It
  then opens `com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility`; the old
  `com.apple.preference.security` URL opens the wrong page on macOS 26/27. The status refreshes when the app becomes active.
- `SkillLinker.link(isInstalled:)`: the CLI passes "command on PATH". The first real install created `~/.pi`,
  `~/.hermes`, `~/.openclaw` and `~/.gemini/config/skills` for agents that were not installed.
### 2026-10-25 — Summon with what is on screen
- `ScreenContext` (Core, tested): reads the frontmost app, its window title and selected text (AX, only if already
  trusted), and the browser front tab or Finder selection (`/usr/bin/osascript` through the runner, Safari plus a
  list of Chromium bundle ids). `prompt()` is the agent's first message and ends with "wait for my question".
- `SummonModel.askAgentAboutScreen()` is used by the agent hotkey and the panel's Ask Agent (row and key). The URL
  route and crash/Activity prompts are unchanged. New `ContextField`s are `selected-text`, `browser-page` and
  `finder-selection`, on by default; `inSnapshot` keeps them out of `summon context`'s hidden list.
### 2026-10-25 — Undo any agent's session (MCP checkpoints + panel row)
- `MCPSession` (actor): the agent name comes from `initialize` `clientInfo.name` (`SummonMCP.agentName`). The first
  non-dry-run `settings_set` creates a checkpoint "<Agent> via MCP" and logs `session.start` with `checkpoint` and
  `agent` refs. `summon mcp` logs `session.end` when stdin closes, and only when something changed.
- `UndoOffer.latest(ActivitySources)` (Core, tested): the newest checkpoint under 12 h old with live settings changes
  (rolled-back ones excluded) and no `session.undo`. `SummonModel.undoOffer` shows it as a panel row with an NSAlert
  confirmation. Owner's rule: actions and problems only, so this is one row and never a list.
### 2026-10-25 — Session-start hooks: agents start knowing this Mac
- `ConnectTarget.Hook`: Claude Code and Codex (`SessionStart` groups), Cursor (`version`/`sessionStart`) and agy (a
  named `summon-context` entry). Summon's entry is the one whose command ends in `context --hook <id>`; others stay.
- `MacContext.hookOutput(for:)`: plain text for claude/codex, `additional_context` for Cursor, `injectSteps` for agy.
- Verified: `claude -p --settings <hook> --tools ""` answered chip, RAM and battery with no tool call.
### 2026-10-25 — `summon connect`: every agent gets the server and a This Mac note
- `ConnectTarget` + `AgentConnector` (Core, tested): 8 targets (owner's list; Gemini CLI excluded, `agy` replaces it).
  Each target uses its own CLI's `mcp add/remove/get` (claude, codex, opencode, hermes, openclaw) or edits the
  `mcpServers` map of a JSON file (cursor, agy, pi). A marked block goes in each instructions file. Backups go to
  `~/.local/state/summon/backups/connect/<stamp>/`. Symlinks are resolved before writing, and non-object JSON is refused.
- Hermes and OpenClaw were added to `AgentRegistry`; agy's install hint is the official curl installer.
- Verified with the real claude/codex/opencode CLIs in a temp HOME: connect, idempotent rerun, disconnect back to the original bytes.
### 2026-10-25 — `summon mcp`: MCP server for every agent
- `MCPServer` (Core): transport-free JSON-RPC 2.0 (initialize, ping, tools, resources), `JSONValue` wire type.
  `SummonMCP`: 10 tools (`mac_context`, `settings_*` through the macctl binary with `--json`, checkpoints, crashes)
  and the resource `mac://context`. `summon mcp` reads stdin line by line; nothing else may print to stdout.
- macctl is called as a binary (as checkpoints and status already do), not linked as a library: summon and macctl
  stay separate packages that move to their own repos, and install.sh ships both. Ids are validated and `--`
  ends options, so tool input cannot become a macctl flag.
- Verified with a real client: `claude -p --mcp-config` called `mac_context` and `settings_get`.
### 2026-10-25 — One SummonOS version
- Root `VERSION` (0.1.0) is the source. `SummonVersion.current` (Core/Version.swift) feeds `summon version`/`--version`
  and the first line + `version` key of `summon doctor`; macctl's ArgumentParser `version:` and Summon.app's
  `CFBundleShortVersionString` carry the same value. `tools/check-workspace.sh` fails when any of them drifts.
- CI: push to `main` + PRs only, PR runs cancel older ones, `macos-15` leg, informational Xcode 27 leg, docs-only skip.
### 2026-10-25 — `summon context`: the Mac snapshot for agents
- `MacContext` (Core, tested) + `MacContextProbe` (live: sysctl, IOKit power, SystemConfiguration, CoreGraphics,
  NSWorkspace, Accessibility only when already trusted; never prompts). `summon context [--json] [--only]`,
  `context fields|hide|show`. JSON dates are ISO 8601 (other commands keep the app's format).
- Privacy: everything on by default (owner, 2026-10-25); `agents.json` `hiddenContext` lists fields turned off,
  shown in Settings › Agents › All Agents. Unknown names are dropped on load.
- First step of the master plan (`tasks/todo.md`): PR 2 is `summon mcp`.
### 2026-10-24 — Agent prompts, skills and notifications aligned
- `SessionBrief` (Core, tested) ends every prompt Summon gives an agent (`summon agent prompt`, crash diagnose,
  `summon fix`, item health, Activity, tasks): folder, checkpoint id + undo command, approval mode, skill files.
  Scheduled runs get `scheduledPreamble` (unattended, never ask or wait, end with a summary). Replaces `promptFooter`.
- Notifications: `CrashAnnouncementPlan` (Core) picks one channel per scan, Summon alert (default) or banner
  (`summon.notifications.crashStyle`); the alert orders front without key (Return typed elsewhere ran Diagnose).
  Task results: the CLI logs, the app posts them from the event log (`EventAnnouncer`, Show Log / Ask Agent);
  the CLI's osascript banner only when the app is not running. Sound and task toggles in Settings › Notifications.
- Prompts reworded (Fix with AI ordered and asks before risky steps; logs are evidence); skills: no owner name in
  `summon-mac`, both approval modes, task logs in ~/Summon/Tasks, one undo command; `diagnose-crash-mac` may fix
  the user's own ~/Summon apps. Mac checks 5–6 in `docs/menubar-panel.md` pending.
### 2026-10-24 — Live menu bar label and VoiceOver announcements
- `MenuBarStatus` (Core, tested) + `MenuBarStatusWatcher` (UI): a running agent's `mm:ss` next to the icon while the
  panel is closed; checks the event log's date every 2 s, re-reads only when it moves. Setting
  `summon.menuBar.showsAgentTime` (default on, Settings › General › Menu Bar).
- Hotkey and URL/CLI opens post a VoiceOver announcement (`PanelOpenGuard.announcement`). Mac checks pending.
### 2026-10-20 — Design skills and public preview preparation
- Six workspace design skills retested: modern LiquidGlass and optional Aqua, Classic, Linen, NeXT, Yosemite styles.
  CI validates routes/references and Swift 6 examples against macOS 15.
- Preserved UI work: Activity filters/detail rows, crash action panel, top-pinned menu resize, and modern Settings.
  Provider icons are attributed to a pinned MIT CodexBar revision in THIRD_PARTY_NOTICES.md.
- Owner authorized publishing all reviewed workspace changes and making SummonOS public. Generated apps keep
  their private-repository policy; this workspace visibility decision does not change it.
### 2026-10-20 — Approved production hardening
- Security: theme text/wallpaper validation, owned skill links, fail-closed publishing, private state/logs,
  best-effort diagnostic redaction. `docs/security-model.md` states actual authority/recovery limits.
- `ProcessExecutor`: process groups, bounded output/logs, timeout escalation/cancellation, no inherited unrelated
  descriptors. Tasks serialize scheduling/runs, freeze new agent/mode/cwd, preserve corrupt state, stop on
  capture failure, return nonzero on failure. Legacy tasks retain prior unattended/default-agent semantics.
- `ExecutionPolicyStore`: new installs use harness controls; existing configured installs retain unattended
  unless explicitly changed. CLI `default execution`, Settings General picker. Migration preserves choices.
- Checkpoint failures persist without stale HEAD; pending macctl journals cannot become capture markers.
  Activity distinguishes failed/pending settings operations. Crash batches retain same-time boundaries.
- Installer stages app/macctl with rollback + ownership receipt; uninstall preserves user data. Release builds
  exact public SHA with provenance and optional signing/notary pipeline. Template caches stay outside sources.
- Verification/outstanding runtime, clean-Mac and signing gates: `docs/plans/2026-10-20-production-readiness.md`.
### 2026-10-19 — Private repo for every new app
- Owner: an agent made end-of-day with no repo; every Summon app should get a private one. `RepoPolicy`
  (`defaults/repos`, missing = always) is the standing approval: `summon project new` runs `makeRepo` (shots → private
  repo → CI → push) without the dialog; `ask` keeps the dialog. Settings › General toggle; `summon default repos`.
  Skill/commands: agents must make sure the repo exists. Always `--private` (tested).
### 2026-10-19 — Project screenshots and the showcase
- `summon project shots` (ShotCommands): menu bar template renders its own panel off-screen via NSHostingView +
  `cacheDisplay` (ImageRenderer draws AppKit buttons as ⛔; appearance must be set on the hosting view), light/dark;
  window apps live via ScreenCaptureKit (`SCScreenshotManager`, desktop-independent window) with screencapture -l
  fallback. Live capture of a menu bar panel fails when the menu bar is full: the status item sits off every display
  (x = -2395 here) and so does its panel. `summon project repo` runs shots before the first push.
- `ProjectShowcase` (Core): README section between `<!-- summon:screenshots -->` markers, `~/Summon/Showcase/index.html`.
### 2026-10-19 — Theme files: OKLCH accepted, palettes checked
- `OKLCH` (Core): `oklch(L C H)` ⇄ hex (Ottosson; verified against an independent Python computation);
  `Theme.decode` normalizes every color to `#RRGGBB`. `ThemeLint`: contrast (text 7/4.5, accent and borders 3,
  terminal 4.5; errors below 4.5/2/2.5) and ANSI hue ranges (warnings). `summon theme check` prints both and fails on
  errors. Shipped community palettes keep their upstream warnings; Summon Dawn's bright cyan fixed (#0077A3).
- summon-art: full theme.json example, real terminal hues, `theme check` must pass. The two agent-made themes rebuilt
  in OKLCH (originals kept as theme.json.summon-backup).
### 2026-10-19 — summon clean
- `SummonCleaner` (Core): plan → Trash (`FileManager.trashItem`), owner's rules: logs newest 20 / ≤30 days, removed
  task folder after 7 days, art job untouched 30 days, Antigravity originals 14 days; Apps never touched; notes for
  unknown apps, themes without a wallpaper, invalid theme.json. Once a day from app launch (`--if-due`, stamp in
  state/clean-last); Settings › General › Clean Now… (preview in the dialog). `summon theme check`.
- Found: agent-made themes (hearts-valley-theme, prance-coffee-style) wrote `oklch(…)` and `//` comments into
  theme.json, so theme list skipped them silently. Root cause: summon-art says "work in OKLCH" without "store #RRGGBB".
### 2026-10-19 — ~/Summon is the one home
- Owner: "everything should be in the Summon folder" (an agent's wallpaper ended in agy's brain folder, its candidates
  in ~/Downloads, its theme in ~/.config). `SummonPaths.summonHome` = ~/Summon; `apps` (= `projects`) Apps/, `art`
  Art/, `taskLogs` Tasks/; Themes is a link to ~/.config/summon/themes (where theme set reads; ~/.config is not a git
  repo here). `SummonHome.ensure|migrate` (`summon home`, install.sh, every app launch): folders, link, .gitignore,
  one-time moves (registry paths updated). Agents and tasks start in ~/Summon. Skills/commands use the new paths.
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
