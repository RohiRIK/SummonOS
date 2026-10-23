# Project Context

## Overview
`macctl`: a Swift CLI that AI agents (and people) use to read, set, diff, apply, and undo macOS
settings natively, with opinionated desired-state profiles. Plan: `docs/plans/2026-10-16-macctl.md`
in the workspace. Agent instructions: workspace skill `MacSetup`.

## Current State
- Targets: `MacCtlCore` (models, `Engine`, `Registry`, `Catalog`, `SystemBackend`, `FileSnapshotStore`,
  `KillallRestarter`, `SystemPermissionProbe`, `ProcessRunner`), `MacCtlCLI` (`macctl`, swift-argument-parser),
  `MacCtlCoreTests` (swift-testing, fake runner).
- Contracts between modules: `Sources/MacCtlCore/Interfaces.swift`.
- Catalog: 38 settings (dock, finder, keyboard, screenshots, appearance, desktop, windows, menubar, documents),
  all `verifiedOn: []`. `minimumOS` gates macOS 26/27-only keys.
- Recovery contract per setting (`Recovery.swift`), `undo --dry-run` (`Engine.previewUndo`), `discover` (`Discovery.swift`).
- Backends: `defaults`, AppleScript (argv only), and `.wallpaper` (`NSWorkspace` on the main actor, behind
  the injectable `WallpaperControlling`; tests use `FakeWallpaper`).
- `SettingBackend.validate` runs live checks (wallpaper file exists) for every value before the first write.
- Data: write-once headers in `~/Library/Application Support/macctl/snapshots/<id>.json` and append-only
  journals in `.../macctl/journal/<id>.jsonl` (ADR `../docs/adr/ADR-macctl-recovery.md`; status lives only in the journal).
- Permissions: Automation (System Events) for dark mode only.

## Constraints
- Values reach scripts only as argv (`on run argv`), never spliced into script text.
- Every write is preceded by a snapshot; all validation happens before the first write.
- `swift-argument-parser` is the only dependency (approved 2026-10-16).
- Lives in the workspace repo for now (`macctl/`); planned move to `mac-ctl-dev` / `mac-ctl`.

## Recent History
### 2026-10-23 — Recovery contract, undo preview, macOS 27 settings, discover
- `RecoveryContract` derived per backend (exact/value/conditional/compare_only + notUndone side effects), in describe,
  list and dry-run notes. `undo --dry-run` mirrors the revert walk read-only. ADR addendum D4.
- Fault-schedule property tests (`ContractTests`): failing write attempts in apply, rollback and undo independently;
  recover must restore the exact starting store. Preview-vs-undo property test.
- `Setting.minimumOS`; new `SideEffect.relaunchApps`; 19 new settings incl. macOS 27 `NSMenuBarUseAgentNavigation`
  (+ `NSMenuEnableMenuBarAgent`, per MacG 2026-08) and macOS 26 `NSMenuEnableActionImages`. No public key for
  macOS 27's Liquid Glass slider: find it on a Mac with `macctl discover`.
### 2026-10-20 — Recoverable serialized transactions
- Cross-process cancellable lock covers planning/backup/write/outcome; snapshots publish without overwrite.
  Optional status/appliedSettings/failure distinguish pending/completed/failed; absent status is legacy completed.
- Failed undo stays retryable. mutation_failed reports recoverySnapshot/appliedSettings; partial failures
  are recoverable, not automatically compensated. New errors: snapshot_exists and transaction_busy.
- Wallpaper snapshots save display UUID/path arrays; undo/redo restore distinct displays, retaining scalar
  compatibility. Missing displays remain retryable after reconnect; deleted files keep skip-with-note behavior.
- 94 tests passed with separate-process lock fixtures; release CLI built. Live settings, actual display
  reconnect and OS matrix remain unverified. Old executables ignore journal outcomes; upgrade for recovery.
### 2026-10-18 — desktop.wallpaper
- New setting `desktop.wallpaper` (path, user risk, no restart): read = main screen, write = every screen,
  keeping each screen's scaling options. Missing file or folder → `invalid_value` before any snapshot or
  write (undo too). `reset` unsupported (no system default). For Summon's `theme set`. Not compiled yet.

### 2026-10-16 — Milestone 1 written, not yet compiled
- Scaffold + four parallel modules (core, backends, catalog, CLI) written in a Linux container with no
  Swift toolchain. Needs `swift build && swift test` and per-key verification on a Mac.

## Recovery journal (ADR macctl-recovery, PR-1)
- `.defaults` I/O goes through `PreferencesStore` (CFPreferences on macOS; memory and plist-file fakes on Linux).
  Prior state is absent / explicit (exact CF type) / inherited; managed keys → `managed_setting`.
- Engine is the only journal writer: header [H1] session_start [K1], per change I/W/A (F on failure, immediate
  rollback), [K2] restarts [E1] session_end [K3]. `undo`, rollback and `recover` share one newest-first revert walk
  (RIj/RVj); recover adds R0/RE. Failpoints: `Failpoint.all` (`MACCTL_FAILPOINT=list`), test mode only.
- `recovery_pending` gates apply/undo; `recover` is idempotent; hand edits → `revert_flagged` + `partial_restore`.
- AppleScript and wallpaper settings are journaled too (state explicit; wallpaper keeps per-display priors).

