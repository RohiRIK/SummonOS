# ADR 0002: Execution policy

Status: accepted (2026-10-03)

## Context

A model, a skill, or an MCP client can propose any operation. None of them is trusted to decide what
runs on the Mac.

## Decision

- **One path to execution:** `PolicyBroker.invoke`. App, CLI, and a future MCP adapter all call it.
- **Trusted registry:** tools are built in and compiled into the app. A `ToolDescriptor` declares id,
  version, input/output schema, minimum OS, capabilities, effect (`read` < `reversibleChange` <
  `change` < `privileged`), resource scope, timeout, cancellability, verification, recovery limits.
  The registry rejects malformed descriptors at startup.
- **Checks on every invocation, before `run`:** known tool → same version as planned → input valid
  against schema → OS supported → targets inside scope → authorization for any effect above `read`
  → host re-read **immediately before running** (capabilities, OS) → run with deadline and
  cancellation → output valid against schema → evidence attributed to the invoked tool.
- **Authorization** binds tool, version, effect, SHA-256 of the canonical input, and the exact
  targets, with an expiry. Any drift invalidates it. Broad requests ("fix my Mac") never imply it.
- **No general shell tool.** `CommandRunner.live(allowlist:)` runs only allowlisted absolute
  executables with argv arrays, a fixed environment (`PATH`, `LANG=C`), capped output, and a
  deadline (SIGTERM, then SIGKILL).
- **Unprivileged by default.** Privileged operations come later, one admin prompt per action
  (workspace `osascript` pattern), and a helper daemon only if that is not acceptable — with caller
  authentication and fixed operations, never a command executor.
- Third-party executable plugins are out of scope until there is real isolation (a manifest is not a sandbox).

## Consequences

- Adding a capability means adding a descriptor, an allowlist entry if needed, and tests: deliberate
  and reviewable.
- `TaskState` makes `executing` reachable only from `awaitingAuthorization`, and the journal refuses
  illegal transitions, so a refusal can never be followed by a write.
