# Current plan: SummonOS master plan — "the agentic layer for the Mac"

Status: draft, awaiting owner review (2026-10-25). Move to `docs/plans/` when done.

## Goal (owner, 2026-10-25)

An AI-native layer on top of macOS that gives every agent the user runs (Claude Code, Codex, Gemini CLI,
Cursor, opencode, ...) more context about the Mac itself. Omarchy's idea, rebuilt as native Mac apps.

Positioning: Omarchy v4 already markets itself as "agentic Linux". Do not claim the idea is new; lead with what
only the Mac version has: native signed Swift binaries, live Mac context, and **undo for anything an agent changed**.

## Where we are (checks run 2026-10-25)

- `main` = `origin/main` @ `3920664`; GitHub `Swift (macOS)` green; `tools/check-workspace.sh` ok; 64 Python tool tests pass.
- This Mac has only CommandLineTools, no Xcode: UI targets and every `swift test` fail to compile locally
  (`#Preview`/`@State`/`@Test` macro plugins missing). macctl and the `summon` CLI build. CI is the only Swift test signal.
- Have: `macctl` (38 settings, set/apply/undo with journal), `summon` CLI + menu bar app (8 agents, checkpoints,
  tasks, crash alerts, session brief, themes, templates), 3 shipped plugins, Claude Code plugin (7 skills, 9 commands).
- Missing for the vision:
  - no MCP server (planned as macctl M2, never built);
  - no single "what is this Mac's state" command;
  - context only reaches agents Summon itself launches (`SessionBrief`);
  - the hooks only log events;
  - no real Gemini CLI entry;
  - 3 agents get no skills;
  - no signed release or update channel.
- Doc drift:
  - `incubator/summon/PROJECT-CONTEXT.md` claims a macctl MCP and gives wrong skill and command counts;
  - `docs/features.md` lists 5 Settings tabs, but the code has 7;
  - `plugins.json` says macctl has 82 tests; it has 94;
  - "gemini" is an alias of Antigravity.

## Phase 0: Unblock (small, first)

- [ ] Owner: install Xcode 27 (or set `DEVELOPER_DIR`) so this Mac can build UI, run tests, previews, `tools/local-ci.sh`.
- [x] Fix the doc drift listed above (PR 1). The 10 "redundant `try`" warnings are artifacts of the missing Testing
      macro plugin (`try #require` is correct); left as is.

## Phase 1: Mac Context Engine (the core of the vision)

One read-only, fast (<300 ms), redacted snapshot of the Mac that any agent can ask for.

- [x] `MacContext` + `MacContextProbe` (SummonCore): one small reader per area. Each provider returns a `Codable` struct and works on its own,
      so one failing area does not break the snapshot.
  - OS/hardware: model, chip, RAM, macOS version.
  - Power: battery, charging, thermal state.
  - Disk: free space per volume.
  - Network: interface, online, VPN on/off.
  - Displays: count, resolution, scale.
  - Frontmost app and window title.
  - Running GUI apps.
  - Appearance: dark mode, accent, wallpaper.
  - Permissions Summon holds (Accessibility, Automation, Full Disk Access): granted or not.
  - ~~Settings drift from `macctl diff`~~: `macctl diff` needs a profile; deferred to the MCP tools.
  - Crashes and hangs in the last day.
  - Agents installed and default agent.
- [x] `summon context [--json] [--only a,b]`: full or partial snapshot; text form is about 14 lines (~60 ms warm).
- [x] Privacy: every field is on by default (owner's choice). The user can turn off SSIDs, window titles, hostnames and
      user paths in Settings › Agents. Reuse `DebugRedactor` for the fields that are turned off.
- [x] Tests: `MacContextTests` (render size and lines, hiding, `--only`, accent, settings round trip, live probe).
      Run on this Mac through a scratch harness (no Xcode); CI runs the real suite.

## Phase 2: Reach every agent

- [x] **MCP server `summon mcp` (stdio, native Swift, no dependencies).** PR 2: 10 tools, verified with Claude Code. Keep it to 15 tools or fewer (agents get worse with
      more than 40).
  - Read tools:
    - `context_get`
    - `settings_list` / `settings_get` / `settings_diff`
    - `apps_running`
    - `crash_list`
    - `checkpoint_list`
  - Write tools (journaled, undoable):
    - `settings_set` and `settings_apply`, which use macctl's recovery contract and return an undo id
    - `settings_undo`
    - `checkpoint_create` and `checkpoint_undo`
  - Resource: `mac://context`.
  - Tests: protocol tests with JSON fixtures, plus one end-to-end run that pipes stdin into the server.
- [x] **`summon connect [agent...] [--dry-run]`.** (PR 2b) Registers the MCP server with each agent the user has. The
      targets (owner, 2026-10-25) are:
  - Claude Code
  - Codex
  - Cursor (editor and `cursor-agent`)
  - opencode
  - Hermes (Nous Research)
  - OpenClaw
  - Antigravity CLI (`agy`)
  - pi. If pi has no MCP support, reach it through its skill and instructions file instead.

  Not Gemini CLI: it is deprecated and replaced by `agy`. Paths: `docs/research/2026-10-25-agent-mcp-configs.md`.
  Use an agent's own `mcp add` CLI where it has one, and otherwise edit its config file.

  It also writes a marked block into each agent's always-loaded instructions file. The block tells the agent "On
  this Mac, call `summon context` / the `summon` MCP". Back up each file first. `summon disconnect` removes only
  Summon's entry and block, keeping any changes the user made since.
- [x] Start hooks (PR 5): `summon connect` adds a session-start hook to Claude Code, Codex, Cursor and agy. Was: the Claude Code plugin's SessionStart hook injects `summon context` (compact) through
      `additionalContext`. Add the same for the other targets where they support a start hook.
- [x] Add Hermes and OpenClaw to the agent registry (`Agent.swift`). Drop the "gemini"/"gemini-cli" aliases'
      Gemini wording, since `agy` is the agent. Give copilot, cursor-agent and grok skill folders where they support them.
- [x] `install.sh` offers `summon connect` at the end (PR #77; only with `--connect` when non-interactive).

## Phase 3: Features worth showing

- [x] **Undo timeline** (owner chose: MCP session checkpoints + one contextual panel row, no list): the panel lists what agents changed on this Mac (macctl journal + checkpoints, grouped by
      agent session), with one-click undo. The demo is: an agent changes Dock, Finder and dark mode through MCP, then one
      click puts everything back.
- [x] **Summon with context:** (on by default like the other context fields, owner 2026-10-25; each can be turned off) the hotkey captures the frontmost app, its selected text, the Finder selection and the
      browser URL, and hands them to the agent so "fix this" works on whatever is on screen. Each capture is opt-in and
      shown before the agent sends it.
- [x] **System-wide theme:** (accent via new macctl setting; VS Code/Cursor theme extension; Neovim colorscheme; one checkpoint) `summon theme <name>` sets wallpaper, accent, dark mode, Terminal/Ghostty, VS Code and nvim
      in one step, undoable. Build it on the existing theme work.
- [x] **Live Mac events for agents:** (30 s snapshot diff in Summon.app, `mac_events` tool, `events --follow`; MCP push notifications not added, most clients ignore them) `summon events --follow` and MCP notifications for network change, low disk,
      thermal pressure, crashes and app launches.

## Phase R: CI and releases (can run alongside Phases 2–3; owner request 2026-10-25)

Today: `swift.yml` runs on every push to any branch **and** on pull requests, so each PR runs twice (two run ids
per job). It builds and tests in debug only, only on `macos-26`. There are no tags, no GitHub Releases, no version
number in `summon` or `macctl`, and `install.sh` needs Xcode because it builds from source.

- [x] **Leaner CI:** (PR #73)
  - Trigger on `push` to `main` plus `pull_request` only, which halves the runs.
  - `concurrency` keyed on the PR number with `cancel-in-progress`.
  - Add a `macos-15` leg for the minimum OS.
  - macOS 27: GitHub has no hosted `macos-27` runner yet (checked 2026-10-25; newest is `macos-26`, default Xcode 26.6).
    - Add an Xcode 27 leg on `macos-26`. Xcode 27 is a public preview there (actions/runner-images#14404). This catches
      macOS 27 SDK and compiler breaks, though not runtime behavior.
    - For runtime on 27, `tools/local-ci.sh <pr>` on the owner's Mac (macOS 27.0.1) posts `local / swift (macOS)`.
      It needs Xcode 27 installed. Make it a required check, or register the Mac as a self-hosted runner.
    - Switch to `macos-27` when GitHub ships that image.
  - A `paths` filter, so a docs-only change skips the Swift jobs.
- [x] **Version stamping:** (PR #73; typed in by hand and guarded by `check-workspace.sh`, not generated from the tag) one SummonOS version (`vX.Y.Z`) generated into Core at build time from the tag.
  `summon --version` and `macctl --version` print it, and `summon doctor` shows it.
- [x] **Release workflow `release.yml`,** (PR #77; v0.1.0 published 2026-10-25) run on a `v*` tag or by hand:
  - Release-mode universal (arm64 + x86_64) builds of `summon`, `macctl` and `Summon.app`.
  - A zip plus `SHA256SUMS`.
  - GitHub artifact attestation (`actions/attest-build-provenance`), so anyone can verify a binary came from this repo.
  - Release notes generated from conventional commits and CHANGELOG.
  - Ad-hoc signed preview by default. Developer ID signing and notarization (existing `tools/notarize-app.sh`)
    run only when the signing secrets are set.
- [ ] **Channels, the Omarchy way:**
  - `stable` comes from tags.
  - `edge` is a rolling prerelease rebuilt from every green `main`.
  - `summon update [--channel stable|edge]` downloads, verifies the checksum, swaps in the new version with rollback,
    then runs `summon doctor`.
- [x] **Binary install:** (PR #77) `install.sh` downloads the latest release by default, so no Xcode is needed. `--from-source`
  keeps today's path.
- [ ] **Homebrew:** a tap `RohiRIK/homebrew-summonos` with a formula for the CLIs and a cask for Summon.app. The release
  workflow bumps it automatically.
- [ ] **More checks:**
  - CodeQL for Swift (free on public repos).
  - `tools/private-scan.sh` in CI.
  - Dependabot for pinned actions.
  - A post-release smoke job on a clean runner: install from the release, then run `summon doctor`, `summon context`
    and `macctl doctor`.

## Phase 4: Ship and show

- [ ] Finish release qualification from `docs/plans/2026-10-20-production-readiness.md`:
  - real install, upgrade and uninstall (the Phase R smoke job covers part of it)
  - recovery and the OS/CPU matrix
- [x] (PR #87; GIFs still placeholders) Rewrite the README around "the agentic layer for the Mac". Add 3 GIFs (`tools/record-demos.sh`): undo timeline,
      summon with context, and the same Mac diagnosed by Claude, Codex and Gemini side by side.
- [ ] `docs/features.md`, `PROJECT-CONTEXT.md`, `plugins.json` and `docs/log.md` updated after each phase.

## Phase 5: UX/UI overhaul (owner, 2026-10-25). Approved; U0, U1, U2, T1, T2 done

Goal: every surface more efficient and slicker; macOS 26 Liquid Glass with a macOS 15 fallback; less clutter;
things easy to find; smooth flows. The templates are the only way apps get built, and the `mac-app` skill drives
agents through them step by step.

Sources: two read-only audits (2026-10-25) of the Summon app, the templates, the skill and the three reference
plugins, with Visual QA screenshots and a real scaffold of every template kind in a temp HOME.
Standing rules still apply:
- The panel holds actions and problems only.
- Settings live only in the Settings window, with one control per row and no explanatory text.
- Everything should look like the system menus.

### U0: See every surface (first, so every UI PR is checked with screenshots)
- [x] Extend `scripts/visual-qa/run.sh` (PR U0) with:
  - `summon://settings/<section>` routes and a loop over the sections
  - `summon://activity`
  - the crash alert (allowed when `SUMMON_VISUAL_QA=1`)
  - seeded panel states: a problem, the undo row, a running agent

  It runs light and dark on macOS 15 and 26.

### U1: Summon quick wins (high impact, small effort)
- [x] Only the `Settings` scene: drop the duplicate `Window("Summon Settings")`, which can open two copies.
- [x] Delete the per-page `detailHeader` and use `.navigationTitle`. Cut every explanatory string: page subtitles,
      footers, skill descriptions, the "System Healthy" card, "Powered by caffeine", the second Quit button.
- [x] **"Needs attention" block in the panel** (crashes, one row per program with a count and Diagnose…; health
      "N problems · Fix…"), shown only when something is wrong. It replaces the health card in Settings › General.
      The docs and the crash alert already promise it.
- [x] No default agent: the panel header becomes an inline menu of installed agents. Auto-pick when there is only one.
- [x] Undo (as an NSAlert: the panel is closed, so there is no window for a sheet): a sheet with the change count, what is not covered, a "Restore N Changes" button and Cancel as the
      default. It doesn't steal focus, and the copy is fixed for themes (created files are removed now). Activity uses the same sheet.
- [x] Menu bar icon: a small dot when there are problems.

### U2: Panel look
- [x] (PR #96) Liquid Glass on macOS 26 (`NSGlassEffectView` behind the panel, none on rows) and `.menu` material on 15.
      Drop the hand-drawn stroke. 320 pt wide, a 22 pt search field, 13 pt rows like the system menus.
- [x] (PR #96, replaced by panel v3: Ask Agent, Make Something, My Apps, one status line, type to search) Ask Agent is the first row, then Needs attention, then the tree. Remove the duplicates (Ask Agent and Undo in
      Agent ›). Merge Install and Update into Setup, for 6 submenus. Drop the theme chip; errors become rows with Retry.

### U3: Settings layout
- [ ] 5 sections:
  - **General:** login, Accessibility, execution, repos, tidy ~/Summon, agent time
  - **Agents:** one list with status plus one action per row; at the top: default agent, terminal, context
    fields; skills; plugins; detail per agent
  - **Appearance:** theme grid, click to apply
  - **Notifications**
  - **Shortcuts**

  The Terminal tab and duplicate pickers go (default agent appears 4 times today, terminal 3 times). My Apps and
  Tasks move to the Activity window's sidebar.
- [ ] Settings search matches row labels ("login", "shortcut", "theme"), not only section names.

### U4: First run
- [ ] A welcome window shown once: Accessibility (live state), default agent (auto-picked), connect an agent
      (Log In…), then Continue. Settings › General reuses the same rows.

### U5: Activity window and alerts
- [ ] Activity: Needs attention, then a pinned Live row (elapsed time, Stop, Open), then history newest first with
      sticky day headers. `.inspector` for details, the filter in a toolbar menu, the title "Activity", system background.
- [ ] Crash alert: notification-banner layout (icon, title, one line, Diagnose, an overflow menu with Mute), glass on
      26. Remove the duplicate logo, the duplicate dismiss and the "SUMMON DIAGNOSTIC" header.

### T1: One canonical template set (PR #95)
- [x] Canonical templates: `incubator/summon/templates/{menubar,menubar-panel,app,cli,screensaver}`. The panel
      starter moves in, and `examples/*-starter` is deleted. `tools/mp new` copies from them (bundle prefix rewritten);
      today it silently copies the menubar starter for `app`/`screensaver` and fails for `cli`.
- [x] A shared kit in every UI template (from the mac-network reference):
  - `Components.swift`: menu rows with hover, module tile
  - `SummonTheme.swift`: reads the Summon theme
  - `Glass.swift`: gated glass, material fallback
  - an Open at Login toggle in Settings
  - `Screenshots.swift` for every kind
  - `scripts/test.sh`, so the gate passes on a Mac with only Command Line Tools
  - a placeholder `AppIcon.icns` plus `CFBundleIconFile` (today every new app shows as "unhealthy")
  - skip the icon check for CLIs
- [x] Panel in the templates: menu rows, 300 to 320 pt, one control per row, a Settings… row that closes the
      panel, footer rows with key hints.
- [x] CI: create every kind with the real `summon project new` in a temp folder and run its `scripts/check.sh`.

### T2: The agent knows how to use the templates (PR #92)
- [x] Rewrite `mac-app/SKILL.md` as exact steps:
  1. Name and shape; say whether a repo will be pushed.
  2. `summon project new <name> --kind <kind>`, never hand-scaffold.
  3. Core test first.
  4. `scripts/check.sh` must be green.
  5. Bundle, open, `pgrep`, `log show`.
  6. `summon project shots` and a check against the panel checklist.
  7. Icon through `summon-art`.
  8. PROJECT-CONTEXT, repo, menu entry, Open at Login.
- [x] Fix the wrong facts:
  - the theme path (`summon theme current` plus `themes/<slug>/theme.json`)
  - `~/Summon/Apps/<name>` in 5 places
  - the repo-policy text
  - the garbled router sentence
  - `summon-migrate` says macOS 14
  - one Settings standard (grouped Form under 3 sections, sidebar from 3 up)

### A1: Agent installer and updater (owner, 2026-10-25)
- [x] (PR #94) Detect how each agent CLI was installed: Homebrew (formula or cask), bun (`~/.bun/bin`), npm global, or its
      own curl script (cursor, agy, hermes, openclaw). Update it the same way it was installed.
- [x] (PR #94) New installs of agents published on npm use **bun** (`bun add -g <pkg>`): codex, opencode, pi, copilot, grok,
      and claude if published there. Agents that are brew-only or curl-only keep their own installer. Existing
      installs keep their method; brew stays brew.
- [ ] Surfaces:
  - done (PR #94): `summon agents install <agent>`, `summon agents update [<agent>|--all]`, and the detected method shown per agent
  - an Install / Update button on each row in Settings › Agents
  - a "N agent updates · Update…" row in the panel's Needs attention

### P1: Reference plugins (separate repos, later)
- [ ] Align mac-network, mac-calendar and mac-breathe with the template kit (glass, panel rows, Settings standard).

### Decisions (owner, 2026-10-25)
1. Repo policy default becomes **`ask`**: no repo until approved in Summon's dialog. Existing installs that chose
   `always` keep it.
2. Built apps: a **grouped Form for under 3 sections, a sidebar from 3 up**.
3. Order approved: U0 → U1 → T1+T2 (in parallel, agents) → U2 → U3 → U4 → U5 → P1.

## Out of scope

A tiling window manager, restyling system chrome (blocked by SIP), an ISO or full-OS install, cloud services.

## Decisions (owner, 2026-10-25)

1. MCP lives in `summon mcp`. One server, one install. macctl is called as a binary rather than linked (PR 2):
   the two packages stay separate, and install.sh ships both.
2. Privacy: context fields are **on by default**. The user can turn each sensitive field (SSID, window titles,
   hostname, user paths) off in Settings › Agents.
3. First PR: Phase 0 + Phase 1 (context engine). The MCP server is PR 2.

4. Releases are ad-hoc signed preview builds for now, with no Apple Developer ID. The notarization path stays
   behind its secrets.
5. The first version is `v0.1.0`. The agent creates a release tag only after the owner's OK for that release.

## Review

(fill in when done)
