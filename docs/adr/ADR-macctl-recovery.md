---
type: Reference
title: "ADR: macctl recovery"
description: Prior state, per-change journal, hand-edit policy and failpoints for macctl undo and recover.
tags: [macctl, recovery, adr]
---

# ADR: macctl recovery — prior state, per-change journal, hand-edit policy

> Copied into the repo for PR-1 from the shared design document (2026-10-20 21:39 IDT revision); private box paths are redacted. Repo paths are relative to `macctl/` unless noted.

Status: proposed (2026-10-20) · Owner: cto-max-grok · Implementer: coder-joe-grok (ships only after Rohi's direct go)
Repo: RohiRIK/SummonOS @ `0e2bfdf`, paths relative to `macctl/` unless noted.

## Context

**How macctl writes today.** `SystemBackend` shells out to `/usr/bin/defaults`: `read`
(`Sources/MacCtlCore/SystemBackend.swift:32-41`), `write <domain> <key> -bool|-int|-float|-string`
(`:52-62`, flags from `:151-170`), `delete` for reset (`:102-108`). Values are parsed back from
`defaults read` *text* using the catalog's type, not the stored type (`:133-149`). The value model has
only 4 cases, bool/int/double/string (`Model.swift:4`, `DefaultsType` `:72`). A missing key and a
missing domain are both read as `nil` by matching stderr text (`SystemBackend.swift:127-131`). Nothing
uses CFPreferences. There is no currentHost scope, no check for managed (MDM-forced) keys, and no
data/date/array/dict support. The 19 catalog settings are all anyHost, in `com.apple.dock`,
`com.apple.finder`, `com.apple.screencapture` and `NSGlobalDomain` (`Catalog.swift:17-164`). Wallpaper
goes through NSWorkspace, and some settings use AppleScript.

**What recovery exists today.** One JSON snapshot per apply or undo:
`~/Library/Application Support/macctl/snapshots/<yyyyMMdd-HHmmss>.json`, mode 0600, directory 0700
(`FileSnapshotStore.swift:16-19, 40-58`). It holds `Change{id, from: Value?, to}`, where `from == nil`
means the key was unset (`Model.swift:138`), plus `status` pending/completed/failed, `appliedSettings`,
`failure` and `undoes` (`Model.swift:157-188`). `Engine.apply` saves a *pending* snapshot before the
first write (`Engine.swift:87, 273-281`). After each write it rewrites the whole file (`:299`); when the
batch ends it records completed or failed (`:303-312`). `Engine.undo` replays `from` in reverse:
`nil` resets the key, anything else is written back (`:102-173`). The undo is itself snapshotted with
`undoes`, so it can be redone. Crash and concurrency protection: `flock` on
`snapshots/.transaction.lock` with a 30 s timeout (`TransactionLock.swift:195-221`, `FileSnapshotStore.swift:71-74`).
Each snapshot is published by linking it into place without overwrite, with a file fsync and a
directory fsync (`:44-57`). Documented limits: partial failures are not compensated automatically;
**undo overwrites a value another app changed** (`../docs/security-model.md:39,47-51`); there is no
automatic recovery command (`README.md:189-200`, `PROJECT-CONTEXT.md:17-31`). Summon's checkpoints depend
on `macctl snapshot list --json` ids (`../incubator/summon/Tests/SummonCoreTests/SystemTests.swift:9-25`).

**Gaps this ADR closes:**
1. The *inherited* case is indistinguishable from *absent*.
2. The prior value's real type is lost: `defaults read` prints a bool as `1`, and the prior is restored
   as the catalog type.
3. Forced keys are never detected.
4. Between a write and its `update`, a crash leaves the outcome unknown.
5. Hand edits are silently overwritten.
6. `FileHandle.synchronize()` is plain `fsync`, which on Darwin does not flush the drive cache.

**Phase 0 decisions carried forward** (tag `archive/mac-assistant`):
- One execution path through a single local broker in Core: `PolicyBroker.invoke`, with checks
  before `run` and the host re-read just before execution (`incubator/mac-assistant/docs/adr/0002-execution-policy.md:12-22`).
- Probes are read-only and never prompt (`ADR 0002:14-15` effect `read`; today `PermissionProbe`, `Interfaces.swift:32-37`).
- Journal transitions are recorded before the next step (`mac-assistant PROJECT-CONTEXT.md:45`).

In macctl the broker role belongs to **`Engine`**, the only `MacCtlService` implementation
(`Engine.swift:3-7`, protocol `Interfaces.swift:102-118`). The CLI (`MacCtlCLI/Wiring.swift:11`) and a
future MCP server both call it.

## Decision

### D1. Prior state: three cases, read through CFPreferences (no `defaults` text parsing)
Add a `PreferencesStore` protocol in MacCtlCore with a `CFPreferencesStore` implementation
(`#if canImport(Darwin)`) and an in-memory fake for Linux CI. The `.defaults` backend uses it.
AppleScript and wallpaper settings keep their backends but still go through the journal (D2) with
`state: explicit`.

Each target is a triple: `(appID, user = kCFPreferencesCurrentUser, host)`. `host` is
`kCFPreferencesAnyHost` (the default) or `kCFPreferencesCurrentHost`, set by a new catalog field, `scope`.

| Step | Call | Outcome |
|---|---|---|
| 0 | `CFPreferencesAppValueIsForced(key, appID)` | true → **refuse**, new error `managed_setting`, before any snapshot. |
| 1 | `CFPreferencesCopyValue(key, appID, user, host)` (exact triple, **not** CopyAppValue) | non-nil → **(b) explicit**. Record its CF type and value. |
| 2 | otherwise `CFPreferencesCopyAppValue(key, appID)` (layered: other host, NSGlobalDomain, managed) | non-nil → **(c) inherited**. Record the value for display only, plus the layer where we can identify it (`global`, `otherHost`, or `unknown`). |
| 3 | otherwise | **(a) absent** |

- **Shadowing.** Also read the opposite host scope. If a currentHost value shadows the anyHost
  key we write, record `shadowedBy: "currentHost"` and warn, because the write would have no visible effect.
- **Type** is taken from `CFGetTypeID`: `bool` (CFBoolean), `int` / `float` (CFNumber +
  `CFNumberIsFloatType`), `string`, `data`, `date`, `array`, `dict`. Container types are stored as
  base64 binary plist so they round-trip losslessly. `Value` grows from 4 cases; the scalar JSON
  encoding stays readable by older snapshots.
- **Registered defaults** (an app's `registerDefaults`) are invisible from another process, so they
  read as (a). Restore behaves the same as for (c), so this is harmless.

**Restore.** (a) and (c) → `CFPreferencesSetValue(key, nil, appID, user, host)`, which deletes only
the explicit key so inheritance resumes. (b) → `CFPreferencesSetValue` with a CF object **rebuilt
from the recorded type**: `kCFBooleanTrue`, never `NSNumber(1)`; an int stays SInt64. Then sync:
`CFPreferencesAppSynchronize(appID)` for anyHost, `CFPreferencesSynchronize(appID, user, currentHost)`
for currentHost. Read back with the exact-triple `CopyValue` to verify.

**Why `defaults delete` is not the inverse of `defaults write`.** If the key already held v0, `write
v1` destroys v0. `delete` then removes the key entirely, so the effective value drops to an
inherited layer or the system default, never v0. It also cannot bring back v0's type (an int written
over a string). The inverse of a write is therefore "delete" only for (a)/(c). For (b) it is "write
v0 with its original type", which requires the journal to have captured v0 first.

**cfprefsd.** Plists are never edited directly, because cfprefsd caches them and would overwrite the
edit. Every read and write goes through the CFPreferences API. Each change records `after` (the
`SideEffect` list, `Model.swift:65`; for example `restart: Dock`) so recovery reruns the same restarts once per batch.

### D2. Per-change journal (append-only JSONL, one file per session)
- **Location.** `~/Library/Application Support/macctl/journal/<sessionID>.jsonl`; directory 0700,
  file 0600, created with `O_CREAT|O_EXCL|O_APPEND|O_NOFOLLOW`.
- **Session id.** The `sessionID` equals the snapshot id, so `macctl undo <id>`, `snapshot list --json`
  and Summon checkpoints keep working. `snapshot list` merges legacy `snapshots/*.json`, which stay
  readable and undoable through today's path.
- **Snapshot header (Q-H).** `snapshots/<id>.json` survives only as a **write-once compatibility header**.
  It is created once at session start with `status: "pending"`, so old binaries never read it as completed,
  then file and directory are fsynced. It is **never rewritten**. Status lives only in the journal, and
  `snapshot list` derives it from there. `SnapshotStore.update` and `Snapshot.recording(...)` are removed.
  Pre-journal snapshots keep `macctl undo <id>` through the legacy path, which may read them but writes
  its own outcome to a journal, never back into the snapshot.
- **Record lines.** Every line is `{"v":1,"seq","ts","op",...}`. Ops: `session_start`, `intent`, `applied`, `failed`,
  `flagged`, `revert_intent`, `reverted`, `revert_flagged`, and
  `session_end{outcome: completed|rolled_back|undone|recovered}`.
  - `revert_intent` carries `ref` (the change's intent seq), `prior`, and `expected` (the value macctl wrote, which it expects to find).
  - `intent` carries the full change: `settingID, domain, key, host, prior{state: absent|explicit|inherited,
    type, value | hmac}, new{type, value | hmac}, after[], sensitive`.
  - The other ops carry `ref` (the intent's `seq`) and, where relevant, `observed{type, value|hmac}`.
  - Status is never rewritten in place. The lifecycle is intent → applied → reverted, expressed as new lines.
- **Write order (apply).** Every journal append is followed by `fcntl(F_FULLFSYNC)`; the first line also fsyncs the directory.
  1. Acquire the lock. Write the snapshot header once (fsync, directory fsync) `[H1]`. Append `session_start` `[K1]`.
  2. Per change *i*: `[Ii.1]` append `intent` `[Ii.2]` F_FULLFSYNC `[Ii.3]`, then the CFPreferences write `[Wi.1]`,
     synchronize `[Wi.2]`, read back, `[Ai.1]` append `applied` + F_FULLFSYNC `[Ai.2]`.
  3. **Failure branch (Q-F):** the write throws or the read-back differs → `[Fi.1]` append `failed` + F_FULLFSYNC `[Fi.2]`,
     then **stop the batch and roll back immediately**. The rollback walks changes i..1 newest first through the
     revert steps (`RIj`/`RVj`). Change *i* is reverted only if its re-read differs from `prior`. It ends with
     restarts, `[E1]` `session_end{rolled_back}` `[K3]`, unlock, and `mutation_failed` is returned.
  4. After the last change: `[K2]` run the restarts `[E1]` append `session_end{completed}` + F_FULLFSYNC `[K3]` unlock.
- **Undo (Q-U).** Undo of a journaled session appends **only revert lines to the same session journal**, never
  `intent`/`applied` lines and never a new session. It walks the applied changes newest first:
  `revert_intent` + F_FULLFSYNC `[RIj]`, then the restore write and synchronize `[RVj]`, then `reverted` + F_FULLFSYNC.
  A hand-edited key gets `revert_flagged` instead. It ends with restarts and `session_end{undone}`.
  Journaled sessions therefore have no redo; legacy snapshots keep their undo-as-new-snapshot path and redo.
- **Recover (Q-R).** Recover acquires the lock `[R0]`, then scans. For each unresolved session (newest first) it
  resolves unknowns, runs the same walk (`RIj`/`RVj`), restarts, and appends `session_end{recovered}` + F_FULLFSYNC `[RE]`.
  Unlock comes after the last session. A crash at any R point followed by a rerun must reach the same byte-identical state.
- **Failpoints** (canonical list; Cider's map L159-166 plus the CTO decisions on QA §2.1 Q-K/F/U/R/H;
  `MACCTL_FAILPOINT=<name>[@n]`, seam per QA §2.2, landed in PR-1). `j` is the change index, so a walk hits `RI3` before `RI2`.
  - **batch:** `H1` (header durable, before `session_start`), `K1` (`session_start` durable, before `I1.1`),
    `K2` (last `Ai.2`, before restarts), `E1` (restarts done, before `session_end`), `K3` (`session_end` durable, before unlock).
    K1-K3 are batch boundaries, not restart brackets, and exist for any number of restarts.
  - **per change:** `Ii.1 Ii.2 Ii.3 Wi.1 Wi.2 Ai.1 Ai.2`; failure branch `Fi.1 Fi.2`.
  - **revert (apply rollback, undo and recover):** `RIj RVj`.
  - **recover:** `R0`, `RE` (per session, `@n`).
  - QA's S1-S5 / Ui.x / C1 and every `snapshot.*`/`status.*` point are retired: nothing rewrites a snapshot any more.
- **Torn lines.** Recovery parses line by line. A final line with no trailing `\n`, or one that is
  not valid JSON, is ignored as torn. A corrupt line *before* the last line stops automatic recovery
  for that session and reports `journal_corrupt`.
- **Unknown outcome** (an `intent` with no `applied`/`failed`, or a `revert_intent` with no `reverted`/`revert_flagged`;
  both are handled the same way). Re-read the exact triple. For a `revert_intent`, "new" means its `expected` value:
  - equals `new` → treat as applied;
  - equals `prior` (absent and still absent counts) → treat as not applied, and append `failed{reason:"not-applied"}`;
  - anything else → `flagged` (`revert_flagged` for a `revert_intent`).
- **Walk invariants** (rollback, undo, recover). Newest seq first. `reverted` and `revert_flagged` are terminal.
  A key already at `prior` gets `reverted` with no write, so a rerun makes no extra writes.
- **Hand-edit policy.** Before reverting, compare the current exact-triple value (type and value, or
  HMAC) with the journal's `new`. On a mismatch, someone edited the key after apply: append
  `revert_flagged{observed}`, **do not overwrite**, continue with the other records, and return them in
  `notes` plus a non-zero `partial_restore` result. An explicit `--force` overwrites flagged keys
  (still journaled), subject to Rohi's call (Q1). This replaces today's documented overwrite (`docs/security-model.md:39`).
- **Concurrency.** One session at a time. Keep the existing flock at `snapshots/.transaction.lock`
  (same path, so older and newer binaries still serialize). It is held from planning to `session_end`
  (`K3`) and for all of recover (`R0`…`RE`) and undo. If an unresolved session exists, apply and undo refuse with
  `recovery_pending <id>` until `macctl recover` runs.
- **Retention.** Prune only sessions that ended (`session_end` with every record terminal), keeping
  the last 100 sessions or 30 days, whichever retains more (Q3). Pruning runs under the lock. A
  session with an open intent or a flag is never pruned.
- **Privacy.** Journals are local only: macctl has no network code, they are never included in
  telemetry, logs or MCP responses, and Summon reads only ids and counts. Settings marked
  `sensitive: true` in the catalog store `type` plus `hmac = HMAC-SHA256(perInstallKey, canonicalValue)`
  instead of the value. The key is in `journal/.key` (0600). Plain SHA-256 is not used, because short
  values such as bools and paths are brute-forceable. Consequence: a sensitive (b) prior can be
  *compared* but not *restored* (Q2).

**Where Engine (the broker) enforces each part:**

| Rule | Engine point |
|---|---|
| forced refusal, prior-state capture, shadow warning | `plan()` (`Engine.swift:243`), before confirmation and any journal line |
| lock + `recovery_pending` gate | entry of `apply` / `undo` / `recover` (`:63-65`, `:102-104`); `R0` sits right after the lock in recover |
| write-once header, `session_start` | `apply()` only, via `SnapshotStore.save` (no `update` in the protocol) |
| intent → write → applied ordering, fsync, `Fi` failure + immediate rollback, restarts, K1-K3/E1 | `write()` (`:285-314`) via a new `ChangeJournal` store; every op name listed in D2 is set by the Engine, none by the store |
| unknown-outcome resolution (intent and revert_intent), backward walk, hand-edit flag, `--force` | one shared revert walk used by apply rollback, `undo()` and new `recover()` |
| sensitive HMAC, 0600, no-export | `ChangeJournal` encoder (the only writer) |
| retention | `ChangeJournal.prune()` at the end of a successful session |

The backend never writes without an intent `seq` from Engine.

### D3. Test plan (Swift Testing; the fake store runs on Linux, real CFPreferences runs on a Mac in a throwaway domain `com.summonos.test.<uuid>`, the prefix QA's test mode enforces)
1. `roundTripAbsent` / `roundTripExplicit` / `roundTripInherited`: apply, then undo, leaves the
   exact triple identical (absent stays absent; an inherited value still comes from NSGlobalDomain, not copied locally).
2. `crashBetweenIntentAndWrite`: `MACCTL_FAILPOINT=I1.3` kills after the intent fsync. Recover sees an
   unchanged value, marks it not-applied and writes nothing. Variant `crashAfterWriteBeforeApplied`
   (`W1.2` and `A1.1`): recover treats it as applied and reverts. The full matrix (every name from
   `MACCTL_FAILPOINT=list`, single and double crash) is PR-2. The oracle is the map's (L167-170): after
   `macctl recover`, every test domain is byte-identical to `pre` via
   `defaults export <dom> - | plutil -convert xml1 -o - -` (value, type and presence, not `defaults read` text).
   "Fully applied" is acceptable only before recover runs.
3. `tornLastLineIgnored`: truncate the last line mid-JSON; recovery still succeeds.
   `corruptMiddleLineRefuses` → `journal_corrupt`.
4. `handEditAfterApplyIsFlagged`: apply, change the key externally, undo. The key keeps the hand
   value, the result is `flagged` / `partial_restore`, and other keys are restored. `forceOverwrites`
   only if Q1 = yes.
5. `forcedKeyRefused`: fake `isForced` → `managed_setting`, no journal file, no write.
6. `currentHostScope`: write and restore at currentHost; the anyHost value is untouched; the shadow
   warning fires when currentHost overrides an anyHost target.
7. `typePreserved`: an int prior comes back as CFNumber int (not string, not bool); bool stays
   CFBoolean; float, data, date, array and dict round-trip byte-equal.
8. **Batch points:** `K1` (crash after `session_start` → recover writes nothing, end state = `pre`), `K2` and `E1`
   (all applied → recover reverts to `pre`), `K3` (`session_end{completed}` durable → nothing to recover; undo still
   works), `H1` (header with no journal → recover adopts it, finds every key at prior, writes nothing).
9. **Failure branch:** fake write error at change 2 of 3, with a crash at `F2.1` and at `F2.2` → after recover, `pre`
   byte-identical. With no crash, the apply returns `mutation_failed`, the end state is `pre`, and the journal ends `rolled_back`.
10. **Undo journal:** an undo of a completed session adds only `revert_intent`/`reverted` lines to the same file
    (assert the op set and that there is no new journal). A crash at `RI2` and at `RV2` → recover finishes it, and the end state is `pre`.
11. **Recover's own crashes:** crash at `R0`, `RIj`, `RVj`, `RE` (`@1`/`@2` with two sessions), rerun → same bytes as an uninterrupted recover.
    `recoverTwice`: the second run writes no journal line and no preference.
12. **Write-once header:** `stat` the header's inode, mtime and SHA-256 after `H1` and at the end of apply, failure, undo
    and recover; all must be unchanged. Old snapshots still undo through the legacy path.
13. Also: `recoverIsIdempotent` (run twice, same state, no extra writes); `newestFirstOrder`;
   `sensitiveStoresHmacOnly` (grep the journal for the plaintext → absent); `lockBlocksSecondSession`;
   `legacySnapshotStillUndoes`.

### D4. Declared guarantees, undo preview, fault schedules (addendum, 2026-10-23)
The journal makes recovery correct; D4 makes its limits visible before a write and tests them as properties.
- **`RecoveryContract`** (`Sources/MacCtlCore/Recovery.swift`), derived from the backend, never hand-written:
  `restore` = `exact` (`.defaults`: absent / explicit / inherited told apart, exact type, read back), `value`
  (AppleScript: no unset state), `conditional` (wallpaper: file and display must still exist), `compare_only`
  (sensitive: hash only). `notUndone` lists side effects undo cannot take back: `restart:<Process>` (undo restarts
  again), `logout`, `relaunch-apps`, `creates-folder`. Shown by `describe` / `list --json`; `--dry-run` adds one note per
  setting whose undo is weaker than `exact` or that leaves a side effect.
- **`undo --dry-run`** (`Engine.previewUndo`): the revert walk's checks in the same order, with no lock and no write:
  `already_restored`, `hand_edited` (or `restore`/`delete` with `--force`), `cannot_restore`, else `restore`/`delete`.
  It refuses with `recovery_pending` when undo would. `wouldSucceed == false` predicts `partial_restore`.
- **Fault schedules** (`Tests/MacCtlCoreTests/ContractTests.swift`): `MemoryPreferencesStore.failAttempts` fails the
  n-th `setValue` from now, so an apply write, its rollback restore and a later undo restore fail independently.
  120 seeds cover every prior state (absent, explicit of another type, inherited from the global domain or the
  other host) and random batches; oracle: after `recover` the whole store equals the starting state, no session is
  pending, and a second `recover` writes nothing. 60 seeds with random hand edits check that the preview's
  flagged set equals the keys undo leaves.
- **`minimumOS`** on `Setting`: `set`/`apply`/`diff` refuse a newer setting with `unsupported` before planning.
- **Out of scope by design:** `/Library/Preferences/FeatureFlags` (root, reboot) and TCC-protected domains are not
  catalog targets; `discover` reads only the current user's domains and never writes.

## Consequences
- Undo becomes exact for every type and scope; inherited and absent restore correctly; hand edits are preserved, not clobbered.
- More fsyncs (two per change with F_FULLFSYNC, roughly milliseconds each). This is acceptable for at most 19 keys per batch.
- New error codes `managed_setting`, `recovery_pending`, `journal_corrupt` and `partial_restore`
  must be added to the README contract (`README.md:172-173`) and handled by Summon.
- Older binaries ignore the journal. Keep the existing "upgrade before recovery" warning.
- Core tests stay on Linux with the fake store, plus a macOS-only CFPreferences suite.

## Alternatives rejected
- **Keep the `defaults` CLI:** loses types (text parsing), cannot tell inherited from absent, cannot see forced keys, and makes host scope awkward.
- **Edit plists directly, or `defaults export/import` the whole domain:** cfprefsd cache races, and
  restoring the whole domain clobbers unrelated keys changed concurrently.
- **Keep the mutable JSON snapshot rewritten per step:** leaves an unknown-outcome window, and a crash during the rewrite loses status.
- **SQLite journal (as in Phase 0):** adds a dependency to a zero-dependency tool; JSONL with fsync is enough for single-writer sessions.
- **Overwrite on hand edit (current behaviour):** silently destroys a user's or an app's later choice.
- **Leave a failed batch half-applied until `recover` (today's behaviour):** replaced by an immediate rollback after
  `Fi.2` (CTO decision Q-F). A crash during that rollback is still finished by `recover`.
- **Rewriting the snapshot status per step (Joe's draft and QA's S/Ui/C points):** dropped. A second mutable
  file creates crash windows the journal already covers.

## Blast radius (from Cider)
Source: Cider's blast-radius map (shared-box document, not in the repo) (macos-cider-grok, at `0e2bfdf`). It has the full 19-row
table (L118-143); the summary per group follows. All rows are `risk: .user`, and every `.defaults` row is anyHost today.

| Group (Catalog lines) | Domain · keys · types | `after` | Managed likelihood | Unknown outcome affects |
|---|---|---|---|---|
| Dock ×6 (L13-53) | `com.apple.dock` · autohide, show-recents bool; tilesize int; orientation, mineffect string; autohide-delay float | restart Dock | medium (autohide, tilesize, show-recents, orientation), low (others) | Dock look and behaviour until recover. `tilesize` is often stored as a real by System Settings (QA R-a), which makes it the type-fidelity canary |
| Finder ×5 (L68-100) | `finder.show-extensions` is **NSGlobalDomain** `AppleShowAllExtensions`; the rest are `com.apple.finder` (ShowPathbar, ShowStatusBar bool, FXPreferredViewStyle string, AppleShowAllFiles bool) | restart Finder | low; `show-hidden` medium | Finder chrome. The global key affects every app's file names, so the **inherited case matters most here** |
| Keyboard ×3 (L113-129) | NSGlobalDomain · KeyRepeat, InitialKeyRepeat int; ApplePressAndHoldEnabled bool | logout (note only) | medium (repeat), low (press-and-hold) | typing; takes effect only after logout |
| Screenshots ×3 (L144-160) | `com.apple.screencapture` · location† (path string; creates the folder), type string, disable-shadow bool | restart SystemUIServer | low | where and how screenshots are saved; `location` holds the home path |
| Appearance ×1 (L173) | AppleScript (System Events, Automation permission) | none | low | system appearance; journaled with `state: explicit` (Q5) |
| Wallpaper ×1 (L195) | NSWorkspace per display (`wallpaperBefore/After`)† | none | low | desktop picture per screen; holds the home path |

† = Q2 sensitive candidates.

**Outside macctl:** Summon's `SummonPaths.macctlSnapshots`, the checkpoint routes in `SummonCore/CommandCatalog.swift`,
and `SummonCoreTests/SystemTests.swift` L9-25 depend on stable `snapshot list --json` ids. Summon's Undo must
surface `partial_restore` and `recovery_pending`. `docs/security-model.md` L39 (today's overwrite) must flip in the same PR (map L65-69, L249-253).

**PR split** (map L15-27):
- **PR-1** = D1 + D2 + the D3 unit tests, including the test-mode seam (`MACCTL_TEST_MODE`, `MACCTL_SNAPSHOT_DIR`,
  `MACCTL_TEST_CATALOG`, `MACCTL_FAILPOINT`).
- **PR-2** = the kill -9 matrix, rebased on PR-1's write order.
- **PR-3** (menu bar) is independent.

## Open questions (for Rohi)
- **Q1.** Provide `--force` to overwrite hand-edited keys on undo? (Proposed: yes, hidden behind an explicit flag with a per-key confirmation.)
- **Q2.** Which keys are sensitive (candidates: `screenshots.location`, wallpaper paths, which contain
  the home path)? And for those, should a hash-only record be accepted (not restorable), or should
  the prior be kept encrypted with a key in the Keychain?
- **Q3.** Retention: 100 sessions or 30 days?
- **Q4.** Should an unresolved session block new applies (proposed) or be auto-recovered on the next run?
- **Q5.** Should the AppleScript and wallpaper settings join the journal in the same PR, or in a follow-up?

## Changelog
- 2026-10-20 21:24 IDT: filled "Blast radius (from Cider)" from Cider's blast-radius map (shared-box document, not in the repo); test-domain prefix → `com.summonos.test.<uuid>`; adopted the map's failpoint names (I/W/A/K/E/RI/RV) and the byte-identical recover oracle.
- 2026-10-20 21:39 IDT: resolved QA §2.1 Q-K/Q-F/Q-U/Q-R/Q-H (CTO calls): batch-level K1-K3, `Fi.1/Fi.2` + immediate rollback, undo = revert lines in the same journal, `R0`/`RE`, write-once snapshot header (new `H1`); test rows 8-12; op names now snake_case.
