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
- [ ] **Summon with context:** the hotkey captures the frontmost app, its selected text, the Finder selection and the
      browser URL, and hands them to the agent so "fix this" works on whatever is on screen. Each capture is opt-in and
      shown before the agent sends it.
- [ ] **System-wide theme:** `summon theme <name>` sets wallpaper, accent, dark mode, Terminal/Ghostty, VS Code and nvim
      in one step, undoable. Build it on the existing theme work.
- [ ] **Live Mac events for agents:** `summon events --follow` and MCP notifications for network change, low disk,
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
- [ ] Rewrite the README around "the agentic layer for the Mac". Add 3 GIFs (`tools/record-demos.sh`): undo timeline,
      summon with context, and the same Mac diagnosed by Claude, Codex and Gemini side by side.
- [ ] `docs/features.md`, `PROJECT-CONTEXT.md`, `plugins.json` and `docs/log.md` updated after each phase.

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
