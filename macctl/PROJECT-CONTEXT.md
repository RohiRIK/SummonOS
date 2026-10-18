# Project Context

## Overview
`macctl`: a Swift CLI that AI agents (and people) use to read, set, diff, apply, and undo macOS
settings natively, Omarchy-style (opinionated desired-state profiles). Plan: `docs/plans/2026-10-16-macctl.md`
in the workspace. Agent instructions: workspace skill `MacSetup`.

## Current State
- Targets: `MacCtlCore` (models, `Engine`, `Registry`, `Catalog`, `SystemBackend`, `FileSnapshotStore`,
  `KillallRestarter`, `SystemPermissionProbe`, `ProcessRunner`), `MacCtlCLI` (`macctl`, swift-argument-parser),
  `MacCtlCoreTests` (swift-testing, fake runner).
- Contracts between modules: `Sources/MacCtlCore/Interfaces.swift`.
- Catalog: 18 settings (dock, finder, keyboard, screenshots, appearance), all `verifiedOn: []`.
- Data: snapshots in `~/Library/Application Support/macctl/snapshots/<id>.json`.
- Permissions: Automation (System Events) for dark mode only.

## Constraints
- Values reach scripts only as argv (`on run argv`), never spliced into script text.
- Every write is preceded by a snapshot; all validation happens before the first write.
- `swift-argument-parser` is the only dependency (approved 2026-10-16).
- Lives in the workspace repo for now (`macctl/`); planned move to `mac-ctl-dev` / `mac-ctl`.

## Recent History
### 2026-10-16 — Milestone 1 written, not yet compiled
- Scaffold + four parallel modules (core, backends, catalog, CLI) written in a Linux container with no
  Swift toolchain. Needs `swift build && swift test` and per-key verification on a Mac.
