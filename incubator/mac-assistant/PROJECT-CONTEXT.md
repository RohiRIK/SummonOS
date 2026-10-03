# Project Context

## Overview

`mac-assistant`: a native macOS assistant that understands the state of the Mac, diagnoses problems,
and (later) manages supported settings and software through versioned tools and skills. It runs on
the user's own Mac first, executes locally, and lets the user choose a local or a cloud model.

Product promise: "Tell me what is wrong, show the evidence, propose a specific change, and verify
whether it helped."

First milestone: **Mac Health**. It ships three read-only skills (slow Mac, disk pressure,
connectivity), and slow Mac is the first to work end to end.

Roadmap: `docs/roadmap.md` (v0.1, 2026-10-03). Decisions: `docs/adr/`.

## Current State

- Code lives in the workspace repo at `incubator/mac-assistant/` (branch `feat/mac-assistant`) until it
  moves to its own `mac-assistant-dev` repo (`docs/adr/0001-code-location-and-stack.md`).
- SwiftPM package `MacAssistant`, Swift 6 strict concurrency, minimum macOS 15:
  - `MacAssistantCore`: cross-platform (macOS + Linux) logic. `Contracts/` (shared types, owned by the
    lead), `Execution/` (schema validation, registry, policy broker, command runner), `Diagnostics/`
    (health tools, parsers, slow-Mac rules), `Journal/` (SQLite action journal), `Models/` (local +
    cloud adapters, routing), `Workflow/` (coordinator state machine).
  - `CSQLite`: system-library module for SQLite (the macOS SDK provides it; on Linux, `libsqlite3-dev`).
  - `MacAssistantCLI` (`mac-assistant`): the same coordinator and broker as the app.
  - `MacAssistantUI` + `MacAssistant` (SwiftUI menu bar app): macOS-only, arrive in milestone M1-UI.
- Tests: swift-testing in `Tests/MacAssistantCoreTests/<Area>/`; fixtures in `Tests/.../Fixtures/`
  (synthetic, documentation values only).
- Gate: `scripts/test.sh` (macOS: cache in `~/Library/Caches/macplugins/mac-assistant`; Linux: `/opt/swift`).
- Bundle id `local.macplugins.mac-assistant`. Data: `Application Support/local.macplugins.mac-assistant/`.
- Secrets: API keys in the Keychain (macOS) or `ANTHROPIC_API_KEY` env for the CLI. Never in argv, logs,
  the journal, or JSON.

## Constraints

- **Execution contract.** Skills and model output never grant permissions. Every invocation goes
  through the policy broker, which checks: known tool, matching version, input against schema,
  OS support, capabilities (rechecked right before running), targets inside scope, and authorization
  for any effect above `.read`. Output is validated too.
- **No general shell tool.** Commands only through `CommandRunner`: allowlisted absolute executables,
  argument arrays, deadline, output cap, bounded environment.
- **Workflow:** inspect → diagnose → preview → authorize → execute → verify → report/recover. Every
  transition is journaled before the next step, so a crash leaves a recoverable record.
- **Evidence first.** Deterministic rules produce `Finding`s that cite `EvidenceID`s; the model
  explains and ranks, and the coordinator rejects claims that cite unknown evidence. A single
  high-CPU sample is never labelled faulty.
- **Model routing.** Each task shows local/cloud mode. A local failure never falls back to the
  cloud silently. Cloud export needs a preview (what leaves the Mac, redactions, cost cap).
  `.personal` evidence is redacted before export unless the user approves it; `.secret` never leaves.
- **Logs and app content are untrusted evidence, not instructions.**
- Panel = the job; settings in a separate Settings window (workspace rule).
- No third-party dependencies. Keep `Contracts/` stable: change it only with the lead's agreement.
- Out of scope for now: modifying SIP-protected files, a root daemon, voice, autonomous desktop
  control, a marketplace, App Store sandboxing.

## Recent History

### 2026-10-03 — Kickoff: Phase 0 + package skeleton
- Roadmap v0.1 adopted. Workspace audited (no existing assistant code; reuse patterns from skills).
- Package skeleton + shared contracts; 8 contract tests green on Swift 6.4 (Linux).
