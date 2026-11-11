# Project Context

## Overview
`macctl`: a Swift CLI that AI agents (and people) use to read, set, diff, apply, and undo macOS
settings natively, with opinionated desired-state profiles. Current public contract:
[`README.md`](README.md) and [`settings catalog`](docs/settings.md). The workspace's
`docs/plans/2026-10-16-macctl.md` is historical design provenance, not current acceptance evidence.
Agent instructions: workspace skill `MacSetup`.

## Current State
- Targets: `MacCtlCore` (models, `Engine`, `Registry`, `Catalog`, `SystemBackend`, `FileSnapshotStore`,
  `KillallRestarter`, `SystemPermissionProbe`, `ProcessRunner`), `MacCtlCLI` (`macctl`, swift-argument-parser),
  `MacCtlCoreTests` (Swift Testing, fakes) and `MacCtlCrashTests` (subprocess kill/recover matrix).
- Contracts between modules: `Sources/MacCtlCore/Interfaces.swift`.
- Catalog: 39 settings (Dock 11, Finder 8, keyboard 3, screenshots 5, appearance 4, desktop 1,
  windows 3, menubar 2, documents 2). All use `user` risk and `verifiedOn: []`.
  `minimumOS` gates the macOS 26 menu-icon and macOS 27 menubar keys; these are declarations, not OS-matrix acceptance.
- Source version: `macctl 0.2.4`, matching workspace `VERSION`; no build/channel/revision identity
  in macctl's version output. Branch implementation does not establish a published release.
- Recovery contract per setting (`Recovery.swift`), `undo --dry-run` (`Engine.previewUndo`), `discover` (`Discovery.swift`).
- Backends: `.defaults` schema uses CFPreferences (37 settings, exact typed prior-state recovery),
  AppleScript (dark mode, value-only recovery, argv only), and `.wallpaper` (`NSWorkspace`,
  conditional per-display restoration behind injectable `WallpaperControlling`; tests use `FakeWallpaper`).
- `SettingBackend.validate` runs live checks (wallpaper file exists) for every value before the first write.
- Data: write-once headers in `~/Library/Application Support/macctl/snapshots/<id>.json` and append-only
  journals in `.../macctl/journal/<id>.jsonl` (ADR `../docs/adr/ADR-macctl-recovery.md`; status lives only in the journal).
- Permissions: Automation (System Events) for dark mode only.

## Constraints
- Values reach scripts only as argv (`on run argv`), never spliced into script text.
- Every mutation is journaled before writing; profile/type/backend preflight precedes the first setting
  write. A no-op or dry-run creates no session. Writes and restores are read back.
- Journaled undo appends to the original session (no redo). Failed write/read-back attempts immediate
  rollback; if rollback throws the session remains pending and `recover` is required. `mutation_failed`
  `appliedSettings` then conservatively lists attempted settings, not verified leftovers.
- Corrupt recovery can restore unrelated sessions before returning `journal_corrupt`; `--abandon`
  quarantines only unreadable journals and does not restore their preferences. Force cannot recreate
  missing wallpaper files/displays or restore a failed third-value write not in undo's applied walk.
- `swift-argument-parser` is the only dependency (approved 2026-10-16).
- Lives in this workspace (`macctl/`). Older repository-split plans are not current delivery promises.

## Recent History
### 2026-11-11 — Source-audited documentation refresh
- Refreshed README CLI grammar/output boundaries, 39-setting catalog, per-backend recovery limits,
  immediate-rollback failure semantics, corrupt-session behavior, retention and accent/Automatic folder caveats.
- Documented external-cache build/tests with `MACCTL_BIN` for the subprocess harness; commands are
  instructions only. No build, test, lint, formatting, demo recording or runtime verification was run.
- Kept recorded macOS 26.6.2 terminal demos and earlier live accent/wallpaper evidence historical;
  no new `verifiedOn` stamps, release claims or broad Finder-window refresh claims.
- Source audit: catalog/model/recovery, Engine planning/session/revert paths, CLI commands/DTO/output/
  wiring, backend/wallpaper, journal/store/test seams, package manifest, crash harness, installer,
  workspace version/build-metadata/CI wiring and relevant macctl commits. Added internal navigation uses relative links.

Earlier entries below record evidence and decisions at their dates, not checks rerun for this checkout.
The October transaction/redo/failed-operation design notes were superseded by the journal contract below.

### 2026-11-10 — Live accent refresh
- `appearance.accent-color` now runs `refreshAppearance` after verified writes and on undo/recovery;
  CoreUI requires both `AppleAquaColorVariantChanged` and `AppleColorPreferencesChangedNotification`.
  These are private notification names, not a public macOS setter contract; keep the reopen-apps fallback.
- macOS 27.2: an already-running AppKit probe received `NSSystemColorsDidChangeNotification` and changed
  blue → purple → blue across apply/undo without restarting. Automatic icon tint resolved to each accent too.
  Folder color is a separate control: Automatic follows the system accent, explicit/custom colors are preserved.
  Native icon APIs were inspected read-only for evidence, not added as a shipping dependency.
- Native `NSWorkspace` renders of the same ordinary folder changed blue → purple after applying Catppuccin;
  this proves the folder-icon asset path, not an already-open Finder window capture.
- The implementation commit records a passing focused dry-run/no-op/apply/undo regression; no
  result was rerun during the documentation refresh.

### 2026-10-25 — Wallpaper read-back race on macOS 27
- Found on the owner's Mac (2 displays, macOS 27.0.1): `set desktop.wallpaper` returned `mutation_failed` ("read-back did not
  match") although the picture had changed. `desktopImageURL` lags about 0.5 s behind the write. `LiveWallpaper` now waits
  up to 3 s for every screen to report its target after `setWallpaper` and `restoreWallpapers`. Verified live: set,
  then `undo`, on both screens.
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
- `recovery_pending` gates mutations and undo preview; `recover` resolves unfinished sessions idempotently.
  Hand edits → `revert_flagged` + `partial_restore`; completed flagged sessions need explicit undo retry.
- AppleScript and wallpaper settings are journaled too (state explicit; wallpaper keeps per-display priors).
- Active side effects batch once: process restarts plus accent refresh (both private CoreUI names).
  Logout/app relaunch remain advisory. Automatic Folder color follows accent; custom choices remain untouched.
  Undo does not remove created folders, restore deleted assets or reverse completed restarts.

