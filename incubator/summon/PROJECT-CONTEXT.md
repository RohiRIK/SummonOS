# Project Context

## Purpose and current baseline

Summon is the native agent layer in the SummonOS workspace: a menu bar app and CLI that launch a chosen coding
agent, supply Mac context, route crash reports, schedule work, manage projects and apply themes through macctl.
It is an original design informed by research, not an Omarchy port or a general-purpose agent sandbox.

This documentation reconciliation began at `18c7688` (2026-11-11) and now includes `main` through PR #126.
The shared base version is `0.2.6` (bumped 2026-11-13); tag `v0.2.5` is the newest pushed tag, `v0.2.6` is not tagged yet. Numbered releases are previews/prereleases.
Stable/Edge are distribution channels; the published Edge artifact can lag this branch. Never infer full
acceptance from a base version, successful installation, green diagnostic job or source implementation.

## Recent changes — 2026-11-11

- `AgentLaunchProblem.swift` turns terminal launch failures into actionable diagnostics (Automation `-1743`,
  timeouts). `summon agent` logs `agent.launch.failed`; the app notifies through `onAgentFailure`.
  Doctor's `config.terminal` checks the app's own Automation permission (`automationStatus`, set only in the app:
  from a shell macOS answers for the terminal). This preserves the implementation merged in PR #126.
- Theme accent synchronization and its verification are summarized below; dated evidence remains in Git history.

## Architecture and durable contracts

- SwiftPM layers: `SummonCore` owns logic/services and state contracts; `SummonMenuUI` contains observable UI
  models and views; `SummonMenu` is the thin app entry point; `SummonCLI` exposes commands. Swift 6, macOS 15
  deployment floor, newer styling/APIs availability-gated. Source builds require the newer SDK used by the app.
- Bundle identity is `local.macplugins.summon`. System-setting changes go through the workspace's `macctl`.
  No passwordless-sudo setup is part of the product contract.
- `plugin/` contains the shipped router/Mac/art/app/test/migration/diagnostic skills, Claude plugin commands and
  session hooks. Supported installed agents receive skill links; agents without a known skill folder receive
  paths in their prompt. The CLI and macctl are prerequisites for the plugin.
- Native panel: `NSStatusItem` + nonactivating `StatusPanel`, one `PanelController`, one retained hosted view.
  Open by click, recordable ⌃⌥Space, `summon panel [--close]` or `summon://panel` / `summon://menu/<id>`.
  Early URL events queue until the controller exists. A second same-bundle-id app activates the running copy
  and exits; it does not forward its launch URL. Do not promise multi-copy URL forwarding.
- Panel home is Ask Agent, Make Something and My Apps, optional setup-attention/Undo, plus Activity/Settings/Quit
  footer. Search is always visible. No separate launcher window, Now/Recent feed, crash list or active-theme
  header pill. History belongs in Activity; preferences in the separate sidebar Settings window.
- Panel click/hotkey focus search; URL/CLI opens do not. Non-click opens guard Return for 300 ms. Submenu Esc
  navigates back; root Esc closes. Returning to the previous app does not close; switching to a third app does.
  The optional menu bar elapsed clock is off by default. See [panel contract](docs/menubar-panel.md).
- Settings pages: General, Agents, My Apps, Terminal, Notifications, Appearance, Setup, Tasks; close-only chrome,
  780–820 pt wide. Activity and Updates are separate foreground windows. Welcome is optional, four steps,
  720 × 480; closing skips it and General/`summon://welcome` can reopen it.
- About uses AppKit's standard singleton from General and the standard About command. `BuildInfo` contains
  marketing version, numeric build, revision/state, channel, configuration and UTC time. Packaging stages one
  identity into compiled constants/plist/manifest. Runtime About does not read Git/network/updater metadata;
  development unknowns remain explicit. Cold launch now explicitly unhides and raises the native window.

## Agent authority and recovery

- Ten launch targets: `claude`, `codex`, `opencode`, `copilot`, `cursor-agent`, `agy`, `pi`, `hermes`, `openclaw`,
  `grok`. No default agent is preselected. Antigravity is `agy`; `gemini` aliases it rather than adding a second
  Gemini CLI implementation.
- Eight connect targets: `claude`, `codex`, `cursor`, `opencode`, `hermes`, `openclaw`, `agy`, `pi`. These configure
  the Summon MCP server and supported instruction/hooks. OpenCode MCP removal can be manual. Connection,
  interactive launch, account/model/plugin probing and headless scheduling are distinct capabilities.
- Five headless task targets: `claude`, `codex`, `opencode`, `agy`, `pi`. New tasks bind agent/execution/directory;
  legacy configured intent remains supported rather than silently changing authority.
- New installations default to Agent controls (`normal`); existing configured installs retain prior execution
  choice. `unattended` bypasses supported harness controls. Normal means the harness's behavior, not an added
  sandbox; some harnesses have no approval prompts.
- Sessions attempt a macctl history marker and a Git commit of `~/.config` when it is a repository. Capture
  warnings are preserved; interactive work can proceed with warnings, while scheduled tasks stop on capture
  failure. Checkpoint undo restores covered settings/config, may include later supported changes, and does not
  undo arbitrary files, package installs or external side effects. Later-created files generally remain except
  explicitly recorded Summon-owned creations. See [security model](../../docs/security-model.md).
- Scheduled outcomes share `TaskResults`: success, failure, cancellation, timeout, interruption. A run UUID exists
  before preflight. Encoded completion details are bounded; committed event persistence is distinct from
  retention/marker/notification failure. Interrupted-marker recovery does not append a contradictory outcome
  after an already committed terminal event. Task leases release before bounded notification delivery.
- Cleanup ranks UUID logs by modification time, protects active/pending evidence under task leases, revalidates
  eligibility before Trash and reports partial failures. Busy/failed candidates do not mark automatic cleanup
  complete. Apps are not cleanup targets. Use preview before apply.

## Projects, inventory and theme behavior

- Nine canonical starters in `templates/`: `menubar`, `menubar-panel`, `launcher`, `hud`, `notch`, `app`, `widget`,
  `cli`, `screensaver`. `ProjectStarter` differs from the four registry `ProjectKind`s: launcher/HUD/notch/panel
  starters register as `menubar`; widget registers as `app`. Widget is the small Xcode-project exception for its
  embedded sandboxed WidgetKit extension; the rest use SwiftPM. Do not imply Summon itself has a widget/notch UI.
- Projects are created under `~/Summon/Apps/<name>` and tracked privately in `~/.config/summon/projects.json`, not
  the workspace registry. Import/register supports existing projects. Agents launched from home/root start in
  `~/Summon`; project-local working directories remain meaningful.
- Repositories default to `ask`: `summon project repo` requests approval and creates a private repository. A
  saved `always` preference remains standing approval. Public publishing is a separate workspace decision.
- Panel and Settings My Apps share six categories, including empty ones: Panel Apps, Themes, Art & Wallpapers,
  Window Apps, Command-Line Tools, Screensavers. All built-in/custom themes stay visible; theme/art entries
  never dispatch an unrelated project with the same name.
- `AppInventoryHealth` deduplicates repair/recommendation counts and AI repair scope. Required missing files,
  referenced images and absent actual build artifacts are repairs. Optional artwork/colors-only wallpaper and
  palette/readability recommendations are not automatic repairs; retain numeric contrast findings separately
  from hue advice. `summon fix --apps` uses inventory defects; `summon fix` remains general Mac diagnosis.
- Theme selection/checkmarks and previous-theme tracking share model state. Preview is not Apply. `ThemeAccent`
  applies the active palette to controls across app surfaces. macctl posts color-refresh notifications after
  accent apply/undo/recovery. Finder Automatic folder colors follow system accent, explicit folder colors remain
  untouched, and some running clients may need reopening. Bundled Catppuccin accent/active border is mauve.

## Runtime ownership and verification boundaries

- Panel/Activity share one off-main source collector, generation-checked publication, explicit interest and
  filesystem invalidation plus slow reconciliation. The status watcher handles file creation/replacement and
  appended event positions rather than writer timestamps. One-second ticks exist only for displayed clocks.
  App termination explicitly stops owners, observers, startup work and hotkeys.
- Automatic update checks default on, are due at launch/24 hours after last check and skip Low Power Mode.
  Update row/tag opens the Updates window. Summon installs only through the explicit verified install/relaunch
  action; optional agent auto-update is a separate preference. Stable follows numbered tags, Edge the published
  rolling artifact. Failed command rows expose details/Fix with AI and password-needed terminal handoff.
- Recorded hosted evidence covers native About identity/keyboard close, Activity terminal delivery and actual
  panel query-value readback, including sustained profiler workloads. A native 13-report equal-timestamp burst
  passed real watcher batching, newest + 12 alert presentation, native Dismiss and subsequent typed search.
  Those results do not prove macOS banner or VoiceOver behavior.
- One earlier native cold launch did not expose a visible About window; `18c7688` adds explicit raising. Do not
  turn the source correction into unrecorded repeated-cold-launch acceptance.
- Release gates still include meaningful completed SwiftUI recordings, controlled comparative GUI profiling,
  actual displayed-frame timing, full retained-memory/retain-graph analysis, native notification scenarios,
  VoiceOver, Reduce Transparency and Reduce Motion. Ordered-front/pre-display signposts are not displayed
  frames; RSS, live malloc totals and retained graphs are different measures; missing evidence never passes.
- No application crash or memory-leak cause is established merely by hardening fixes. Historical evidence and
  original-source findings remain in the [runtime audit](../../docs/plans/2026-11-08-runtime-audit.md).

## Documentation reconciliation — 2026-11-11

Reviewed current source and the `3f37adf` → `18c7688` history for the public README, changelog, panel contract and
UX audit. Corrected stale panel/search/Settings layouts, agent capability sets, update channels/window, nine
starters, recovery limits, My Apps repair/recommendation counts, accent synchronization and native About identity.
The two native UI references now have OKF metadata and distinguish implementation from verification/release.
All nine starter READMEs were reviewed; only demonstrated mismatches are changed. This documentation work
runs no builds, tests, linters, UI audits or profiling and adds no fresh runtime acceptance claim.

Use the [documentation home](../../docs/index.md), [public overview](README.md), [UX audit](docs/ux-audit.md),
[status](../../docs/status.md) and [changelog](CHANGELOG.md) for current navigation. The changelog retains dated
historical entries. Original plans/research, archived `archive/mac-assistant`, and prior memory revisions in Git
preserve provenance; rejected panel layouts and superseded defaults are not current contracts. This concise
memory intentionally excludes personal installation inventories, local build numbers and recovery identifiers.
