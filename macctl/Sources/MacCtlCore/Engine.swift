import Foundation

/// The one implementation of `MacCtlService`: validates, plans, journals, writes, restarts, undoes,
/// recovers (ADR D1/D2; Engine is the broker of ADR 0002).
///
/// Every mutation runs under the transaction lock, refuses while an earlier session is unresolved
/// (`recovery_pending`), writes a write-once snapshot header and then an append-only journal in which
/// each change's intent is durable before the real write. A failed change rolls the batch back at
/// once; a crash is rolled back by `macctl recover`.
public struct Engine: MacCtlService {
    public let registry: Registry
    private let backend: any SettingBackend
    private let restarter: any Restarter
    private let probe: any PermissionProbe
    private let snapshotStore: any SnapshotStore
    private let journals: any JournalStore
    private let osVersion: @Sendable () async -> String
    private let now: @Sendable () -> Date

    /// `journal` defaults to `<snapshots>/../journal` for a `FileSnapshotStore`, else in memory.
    public init(
        registry: Registry,
        backend: any SettingBackend,
        restarter: any Restarter,
        probe: any PermissionProbe,
        snapshots: any SnapshotStore,
        journal: (any JournalStore)? = nil,
        osVersion: @escaping @Sendable () async -> String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.registry = registry
        self.backend = backend
        self.restarter = restarter
        self.probe = probe
        self.snapshotStore = snapshots
        self.journals = journal ?? (snapshots as? FileSnapshotStore).map { FileJournalStore(directory: $0.journalDirectory) }
            ?? MemoryJournalStore()
        self.osVersion = osVersion
        self.now = now
    }

    // MARK: - Catalog

    public var settings: [Setting] { registry.all }

    public func setting(_ id: String) throws -> Setting {
        try registry.setting(id)
    }

    public func get(_ id: String) async throws -> Value? {
        let setting = try registry.setting(id)
        try await requirePermissions([setting])
        if case .defaults = setting.backend {
            let prior = try await backend.priorState(setting)
            return effective(prior, setting) ?? setting.systemDefault.map(setting.type.normalize)
        }
        return try await backend.read(setting) ?? setting.systemDefault.map(setting.type.normalize)
    }

    public func parse(_ text: String, for id: String) throws -> Value {
        let setting = try registry.setting(id)
        return try setting.type.parse(text, id: id)
    }

    // MARK: - Diff / apply

    /// `Change.from` is the explicit stored value (nil = unset or inherited); a setting is listed
    /// only when its effective value differs from the target.
    public func diff(_ profile: Profile) async throws -> [Change] {
        let targets = try resolve(profile)
        try await requirePermissions(targets.map(\.setting))
        return try await plan(targets).map(\.change)
    }

    public func apply(_ profile: Profile, dryRun: Bool, confirmed: Bool) async throws -> ApplyResult {
        let transaction = dryRun ? nil : try await snapshotStore.acquireTransaction()
        defer { transaction?.release() }
        if !dryRun { try prepareMutation() }
        let targets = try resolve(profile)
        try await requirePermissions(targets.map(\.setting))
        let planned = try await plan(targets)

        // Confirmation is required only for risky settings that would actually change.
        if !dryRun && !confirmed, let risky = planned.first(where: { $0.setting.risk >= .admin }) {
            throw MacCtlError.needsConfirmation(id: risky.setting.id, risk: risky.setting.risk)
        }

        let changes = planned.map(\.change)
        let lost = planned.compactMap { item -> String? in
            let values = item.change.wallpaperBefore?.map { Value.string($0.path) }
                ?? item.change.from.map { [$0] } ?? []
            guard let reason = values.compactMap({ unrestorable($0, for: item.setting) }).first else { return nil }
            return "Undo cannot restore the current \(item.setting.id) (\(reason))."
        }
        let shadows = planned.compactMap { item -> String? in
            guard item.change.prior?.shadowedBy == .currentHost else { return nil }
            return "\(item.setting.id): shadowedBy: currentHost. A currentHost value overrides this key, so the change may have no visible effect."
        }
        let notes = lost + shadows + Self.notes(for: planned.map(\.setting))
        guard !dryRun, !planned.isEmpty else {
            return ApplyResult(snapshotID: nil, changes: changes, dryRun: dryRun, notes: notes)
        }
        let run = try await runSession(planned, undoes: nil)
        pruneJournals()
        return ApplyResult(snapshotID: run.id, changes: changes, dryRun: false, notes: notes + run.notes)
    }

    // MARK: - Snapshots / undo / recover

    /// Every session, newest first: journaled sessions (status derived from the journal; the header
    /// on disk keeps `pending` forever) merged with pre-journal snapshots.
    public func snapshots() throws -> [Snapshot] {
        var byID: [String: Snapshot] = [:]
        for snapshot in try snapshotStore.list() { byID[snapshot.id] = snapshot }
        for id in try journals.ids() {
            guard let session = try? loadSession(id) else { continue }
            byID[id] = session.snapshot(header: byID[id])
        }
        return byID.values.sorted { a, b in
            a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id.compare(b.id, options: .numeric) == .orderedDescending
        }
    }

    public func undo(snapshotID: String?) async throws -> ApplyResult {
        try await undo(snapshotID: snapshotID, force: false)
    }

    /// A journaled session is reverted in place: only `revert_intent`/`reverted`/`revert_flagged`
    /// lines are added to its journal, then `session_end{undone}` (ADR Q-U, no redo). A key changed by
    /// hand since macctl wrote it is left alone and reported (`partial_restore`) unless `force`
    /// (ADR Q1). A pre-journal snapshot is undone through a new journaled session (`undoes: <id>`),
    /// never by rewriting the snapshot; undoing that session again is the old redo.
    public func undo(snapshotID: String?, force: Bool) async throws -> ApplyResult {
        let transaction = try await snapshotStore.acquireTransaction()
        defer { transaction.release() }
        try prepareMutation()
        let id: String
        if let snapshotID {
            guard FileSnapshotStore.isSafeID(snapshotID) else { throw MacCtlError.snapshotNotFound(snapshotID) }
            id = snapshotID
        } else {
            let all = try snapshots()
            let inEffect: (Snapshot) -> Bool = { $0.status == nil || $0.status == .completed }
            let undone = Set(all.filter(inEffect).compactMap(\.undoes))
            guard let newest = all.first(where: { inEffect($0) && $0.undoes == nil && !undone.contains($0.id) }) else {
                throw MacCtlError.noSnapshots
            }
            id = newest.id
        }
        if try journals.contents(id) != nil {
            return try await undoJournaled(id, force: force)
        }
        return try await legacyUndo(try snapshotStore.load(id: id))
    }

    /// Rolls back every unresolved session (unfinished journal, or a header with no journal), newest
    /// first, and ends each with `session_end{recovered}`. Idempotent: a rerun appends nothing and
    /// writes nothing. A journal corrupt before its last line is skipped with `journal_corrupt`, as
    /// is any older session touching the same settings (QA R-c); `abandon` sets one aside after the
    /// user inspected it.
    public func recover(force: Bool = false, abandon: String? = nil) async throws -> RecoverResult {
        let transaction = try await snapshotStore.acquireTransaction()
        defer { transaction.release() }
        Failpoint.hit("R0")
        removeTemporaries()
        if let abandon {
            guard FileSnapshotStore.isSafeID(abandon) else { throw MacCtlError.snapshotNotFound(abandon) }
            do {
                _ = try loadSession(abandon)
                throw MacCtlError.invalidProfile("journal \(abandon) is readable; run `macctl recover` without --abandon")
            } catch MacCtlError.journalCorrupt {
                try journals.quarantine(abandon)
            }
        }
        var result = RecoverResult(sessions: [], notes: [])
        var corrupt: [(id: String, line: Int)] = []
        var blockedSettings: Set<String> = []
        for id in try unresolvedIDs() {
            let session: Session
            do {
                session = try loadOrAdoptSession(id)
            } catch MacCtlError.journalCorrupt(_, let line) {
                corrupt.append((id, line))
                if let header = try? snapshotStore.load(id: id) { blockedSettings.formUnion(header.changes.map(\.id)) }
                continue
            }
            let touched = Set(session.intents.compactMap(\.settingID))
            if !touched.isDisjoint(with: blockedSettings) {
                result.notes.append("Skipped \(id): it touches settings of a newer session whose journal is corrupt.")
                blockedSettings.formUnion(touched)
                continue
            }
            let writer = try appender(for: session)
            let report = try await walk(session, writer: writer, mode: .recover, force: force)
            try writer.append(.sessionEnd, points: (nil, "RE")) { $0.outcome = Snapshot.Status.recovered.rawValue }
            result.sessions.append(report.summary(id))
            result.notes += report.notes
        }
        if let first = corrupt.first { throw MacCtlError.journalCorrupt(snapshotID: first.id, line: first.line) }
        let flagged = result.sessions.flatMap(\.flagged)
        if let session = result.sessions.first(where: { !$0.flagged.isEmpty }) {
            throw MacCtlError.partialRestore(snapshotID: session.id, flagged: flagged)
        }
        return result
    }

    // MARK: - Planning

    fileprivate struct Target {
        let setting: Setting
        let value: Value
    }

    /// One change of a session, fully decided before the first journal line.
    fileprivate struct Planned {
        let setting: Setting
        /// What is journaled and reported (`prior`/`new` already redacted for sensitive settings).
        let change: Change
        /// The value to write; nil deletes the key (undo of a pre-journal snapshot of an unset key).
        let target: Value?
        /// Undo of a pre-journal wallpaper snapshot: the per-display pictures to put back.
        var wallpapersTarget: [DisplayWallpaper]? = nil
    }

    /// Looks up and validates every profile entry (sorted by id) before anything is read or written.
    private func resolve(_ profile: Profile) throws -> [Target] {
        var targets: [Target] = []
        for (id, raw) in profile.settings.sorted(by: { $0.key < $1.key }) {
            let setting = try registry.setting(id)
            let value = try setting.type.coerce(raw, id: id)
            try backend.validate(value, for: setting)
            targets.append(Target(setting: setting, value: value))
        }
        return targets
    }

    /// Captures each target's prior state (refusing managed keys before anything is journaled) and
    /// keeps only targets whose effective value (explicit, else inherited, else system default) differs.
    private func plan(_ targets: [Target]) async throws -> [Planned] {
        var planned: [Planned] = []
        for target in targets {
            let prior = try await backend.priorState(target.setting)
            let wallpapers = try await backend.wallpapers(for: target.setting)
            let current = effective(prior, target.setting) ?? target.setting.systemDefault.map(target.setting.type.normalize)
            let allDisplaysMatch = wallpapers?.allSatisfy { Value.string($0.path).sameValue(as: target.value) } ?? true
            if let current, current.sameValue(as: target.value), allDisplaysMatch { continue }
            planned.append(Planned(
                setting: target.setting,
                change: try journaledChange(target.setting, prior: prior, target: written(target.value, for: target.setting),
                                            display: target.value, wallpapers: wallpapers),
                target: target.value))
        }
        return planned
    }

    /// The reported and journaled form of a change. Sensitive settings keep only type and HMAC.
    private func journaledChange(_ setting: Setting, prior: PriorState, target: TypedValue?, display: Value,
                                 wallpapers: [DisplayWallpaper]?, wallpaperAfter: [DisplayWallpaper]? = nil) throws -> Change {
        let sensitive = setting.sensitive
        let key = { try journals.hmacKey() }
        let from = sensitive ? nil : (prior.state == .explicit ? effective(prior, setting) : nil)
        return Change(id: setting.id, from: from, to: sensitive ? .string("(sensitive)") : display,
                      wallpaperBefore: wallpapers, wallpaperAfter: wallpaperAfter,
                      prior: try prior.redacted(sensitive: sensitive, key: key),
                      new: try RecordedValue.record(target, sensitive: sensitive, key: key))
    }

    /// The catalog-typed value a prior state makes effective (explicit or inherited), or nil.
    private func effective(_ prior: PriorState, _ setting: Setting) -> Value? {
        guard prior.state != .absent, let value = prior.value else { return nil }
        if case .defaults(_, _, let type) = setting.backend { return value.catalogValue(type) }
        return value.value
    }

    /// The exact typed value a write of `value` stores.
    private func written(_ value: Value, for setting: Setting) -> TypedValue {
        if case .defaults(_, _, let type) = setting.backend { return TypedValue(writing: value, as: type) }
        return TypedValue(value)
    }

    /// Checks each distinct permission without prompting; throws on the first missing one.
    private func requirePermissions(_ settings: [Setting]) async throws {
        var seen: [Permission] = []
        for setting in settings {
            for permission in setting.permissions where !seen.contains(permission) {
                seen.append(permission)
            }
        }
        for permission in seen {
            let granted = await probe.isGranted(permission)
            guard granted else {
                throw MacCtlError.permissionMissing(permission, settingsURL: probe.settingsURL(for: permission))
            }
        }
    }

    // MARK: - Undo

    private func undoJournaled(_ id: String, force: Bool) async throws -> ApplyResult {
        let session = try loadSession(id)
        let status = session.status
        let canForce = force && status != .pending && !session.flaggedSettings.isEmpty
        guard status == .completed || canForce else {
            return ApplyResult(snapshotID: id, changes: [], dryRun: false,
                               notes: ["\(id) is \(status.rawValue); nothing to undo."])
        }
        try await requirePermissions(session.intents.compactMap { $0.settingID.flatMap { try? registry.setting($0) } })
        let writer = try appender(for: session)
        let report = try await walk(session, writer: writer, mode: .undo, force: force)
        let outcome = status == .completed ? Snapshot.Status.undone.rawValue : (session.lastEnd?.outcome ?? "undone")
        try writer.append(.sessionEnd) { $0.outcome = outcome }
        if !report.flagged.isEmpty {
            throw MacCtlError.partialRestore(snapshotID: id, flagged: report.flagged)
        }
        return ApplyResult(snapshotID: id, changes: report.changes, dryRun: false,
                           notes: report.notes + Self.notes(for: report.reverted))
    }

    /// Undo of a pre-journal snapshot: reads it, never writes it. Its restores run as a new
    /// journaled session (`undoes: <id>`), with fresh prior states, so they are crash-safe too.
    private func legacyUndo(_ snapshot: Snapshot) async throws -> ApplyResult {
        // Resolve every id before touching anything. A snapshot lists each id once; if not, the
        // earliest entry holds the original value, so it wins.
        var entries: [(setting: Setting, restore: Value?, wallpapers: [DisplayWallpaper]?)] = []
        var seen: Set<String> = []
        for change in snapshot.changes where seen.insert(change.id).inserted {
            let setting = try registry.setting(change.id)
            entries.append((setting: setting, restore: change.from, wallpapers: change.wallpaperBefore))
        }
        entries.reverse()
        try await requirePermissions(entries.map { $0.setting })

        var planned: [Planned] = []
        var skipped: [String] = []
        for entry in entries {
            let setting = entry.setting
            let prior = try await backend.priorState(setting)
            let current = try await backend.read(setting)
            let currentDisplays = try await backend.wallpapers(for: setting)
            if let saved = entry.wallpapers {
                if currentDisplays == saved { continue }
                guard let restoredValue = entry.restore ?? saved.first.map({ Value.string($0.path) }) else {
                    throw MacCtlError.invalidProfile("snapshot has no saved wallpaper value for \(setting.id)")
                }
                if let reason = saved.compactMap({ unrestorable(.string($0.path), for: setting) }).first {
                    skipped.append("Could not restore \(setting.id): \(reason). Left as is.")
                    continue
                }
                var item = Planned(setting: setting,
                                   change: try journaledChange(setting, prior: prior, target: written(restoredValue, for: setting),
                                                               display: restoredValue, wallpapers: currentDisplays,
                                                               wallpaperAfter: saved),
                                   target: restoredValue)
                item.wallpapersTarget = saved
                planned.append(item)
            } else if let restore = entry.restore {
                let value = setting.type.normalize(restore)
                if let current, current.sameValue(as: value) { continue }
                if let reason = unrestorable(value, for: setting) {
                    skipped.append("Could not restore \(setting.id): \(reason). Left as is.")
                    continue
                }
                planned.append(Planned(setting: setting,
                                       change: try journaledChange(setting, prior: prior, target: written(value, for: setting),
                                                                   display: value, wallpapers: currentDisplays),
                                       target: value))
            } else {
                // Was unset: delete the key. Nothing to do when it is already unset.
                guard prior.state == .explicit else { continue }
                planned.append(Planned(setting: setting,
                                       change: try journaledChange(setting, prior: prior, target: nil,
                                                                   display: setting.systemDefault ?? current ?? .string(""),
                                                                   wallpapers: currentDisplays),
                                       target: nil))
            }
        }
        // A completed no-op session is recorded too: an already-restored snapshot must not block older history.
        let run = try await runSession(planned, undoes: snapshot.id)
        return ApplyResult(snapshotID: run.id, changes: planned.map(\.change), dryRun: false,
                           notes: skipped + Self.notes(for: planned.map(\.setting)) + run.notes)
    }

    // MARK: - Doctor

    public func doctor() async -> DoctorReport {
        let version = await osVersion()
        var checks: [DoctorReport.Check] = []

        var permissions: [Permission] = []
        for setting in registry.all {
            for permission in setting.permissions where !permissions.contains(permission) {
                permissions.append(permission)
            }
        }
        for permission in permissions {
            let granted = await probe.isGranted(permission)
            checks.append(DoctorReport.Check(
                name: Self.name(of: permission),
                ok: granted,
                detail: granted ? "granted" : "not granted",
                fixURL: granted ? nil : probe.settingsURL(for: permission)
            ))
        }

        if let diagnostics = snapshotStore as? any SnapshotStoreDiagnostics {
            let result = diagnostics.writableCheck()
            checks.append(DoctorReport.Check(name: "Snapshots writable", ok: result.ok, detail: result.detail))
        } else {
            do {
                let count = try snapshotStore.list().count
                checks.append(DoctorReport.Check(name: "Snapshots writable", ok: true, detail: "\(count) snapshots"))
            } catch {
                checks.append(DoctorReport.Check(name: "Snapshots writable", ok: false, detail: "\(error)"))
            }
        }

        do {
            let open = try unresolvedIDs()
            checks.append(DoctorReport.Check(
                name: "No unfinished operations", ok: open.isEmpty,
                detail: open.isEmpty ? "none" : "\(open.joined(separator: ", ")): run `macctl recover`"))
        } catch {
            checks.append(DoctorReport.Check(name: "No unfinished operations", ok: false, detail: "\(error)"))
        }
        // Legacy `failed` snapshots are not adopted by recover (old contract: partial writes stay);
        // list them so they stay visible.
        if let legacyFailed = try? snapshotStore.list().filter({ $0.status == .failed })
            .filter({ (try? journals.contents($0.id)) == nil }).map(\.id), !legacyFailed.isEmpty {
            checks.append(DoctorReport.Check(
                name: "Older failed operations", ok: true,
                detail: "\(legacyFailed.joined(separator: ", ")): partial writes were left in place; `macctl undo <id>` reverts one"))
        }

        return DoctorReport(macOSVersion: version, checks: checks)
    }

    // MARK: - Private

    /// Runs each distinct restart once, in name order; every restart is attempted and the failures
    /// come back as notes (the values are already written). `.logout` becomes a note elsewhere.
    fileprivate func runRestarts(for settings: [Setting]) async -> [String] {
        var effects: Set<SideEffect> = []
        for setting in settings {
            for effect in setting.after {
                if case .restart = effect { effects.insert(effect) }
            }
        }
        var failures: [String] = []
        for effect in effects.sorted(by: { Self.effectName($0) < Self.effectName($1) }) {
            do { try await restarter.run([effect]) } catch {
                failures.append("\(Self.effectName(effect)) failed (\(error)); restart it by hand to see the change.")
            }
        }
        return failures
    }

    static func effectName(_ effect: SideEffect) -> String {
        switch effect {
        case .restart(let process): "restart:\(process)"
        case .logout: "logout"
        }
    }

    /// Why `value` can no longer be written (for example a deleted wallpaper file), or nil.
    private func unrestorable(_ value: Value, for setting: Setting) -> String? {
        do {
            try backend.validate(value, for: setting)
            return nil
        } catch let MacCtlError.invalidValue(_, _, reason) {
            return reason
        } catch {
            return "\(error)"
        }
    }

    private static func notes(for settings: [Setting]) -> [String] {
        let logoutIDs = settings.filter { $0.after.contains(.logout) }.map(\.id)
        guard !logoutIDs.isEmpty else { return [] }
        return ["Log out and back in for these changes to take effect: \(logoutIDs.joined(separator: ", "))"]
    }

    private static func name(of permission: Permission) -> String {
        switch permission {
        case .automation(let bundleID): "Automation: \(bundleID)"
        case .accessibility: "Accessibility"
        case .fullDiskAccess: "Full Disk Access"
        }
    }
}

// MARK: - Journaled sessions (ADR D2)

/// What `macctl recover` did, per session.
public struct RecoverResult: Sendable, Hashable, Codable {
    public struct SessionReport: Sendable, Hashable, Codable {
        public let id: String
        /// Changes rolled back (setting ids, newest first).
        public let reverted: [String]
        /// Intents whose write never happened (resolved by re-reading).
        public let notApplied: [String]
        /// Changed since macctl wrote them (or a third value on read-back); left as they are.
        public let flagged: [String]
    }

    public var sessions: [SessionReport]
    public var notes: [String]
    /// Number of settings written back. 0 on a second run.
    public var changes: Int { sessions.reduce(0) { $0 + $1.reverted.count } }
}

extension Engine {
    fileprivate enum WalkMode { case rollback, undo, recover }

    fileprivate struct WalkReport {
        var reverted: [Setting] = []
        var notApplied: [String] = []
        var flagged: [String] = []
        var changes: [Change] = []
        var notes: [String] = []

        func summary(_ id: String) -> RecoverResult.SessionReport {
            .init(id: id, reverted: reverted.map(\.id), notApplied: notApplied, flagged: flagged)
        }
    }

    /// Under the lock, before any mutation: remove temp files a SIGKILL left behind (QA R-g) and refuse
    /// while an earlier session is unresolved (ADR Q4: block, never auto-recover silently).
    fileprivate func prepareMutation() throws {
        removeTemporaries()
        if let id = try unresolvedIDs().first { throw MacCtlError.recoveryPending(snapshotID: id) }
    }

    fileprivate func removeTemporaries() {
        (snapshotStore as? FileSnapshotStore)?.removeTemporaries()
        journals.removeTemporaries()
    }

    /// Unresolved sessions, newest first: a journal that is unfinished or corrupt, or a `pending`
    /// header with no journal: a crash at H1, or an older macctl killed mid-batch. A legacy `failed`
    /// snapshot is not adopted: the old contract left its partial writes in place on purpose, so it
    /// neither gates nor gets rolled back (`macctl undo <id>` still reverts it; Max, #62 review). Headers whose journal was set aside with `--abandon` no longer count.
    fileprivate func unresolvedIDs() throws -> [String] {
        var found: [(Date, String)] = []
        let journaled = Set(try journals.ids())
        for id in journaled {
            do {
                let session = try loadSession(id)
                if session.unresolved { found.append((session.createdAt, id)) }
            } catch MacCtlError.journalCorrupt {
                found.append((.distantFuture, id))
            }
        }
        for header in try snapshotStore.list()
        where header.unresolved && !journaled.contains(header.id) && !journals.isQuarantined(header.id) {
            found.append((header.createdAt, header.id))
        }
        return found.sorted { a, b in
            a.0 != b.0 ? a.0 > b.0 : a.1.compare(b.1, options: .numeric) == .orderedDescending
        }.map(\.1)
    }

    fileprivate func loadSession(_ id: String) throws -> Session {
        guard let data = try journals.contents(id) else { throw MacCtlError.snapshotNotFound(id) }
        let parsed = try JournalCodec.parse(data, id: id)
        return Session(id: id, records: parsed.records, tornTail: parsed.tornTail)
    }

    /// A `pending` header with no journal (crash at H1, or an older macctl killed mid-batch) is
    /// adopted: its changes become intents with unknown outcome, which the walk resolves by
    /// re-reading, exactly like a crash after an intent. Nothing is read from or written to the header.
    fileprivate func loadOrAdoptSession(_ id: String) throws -> Session {
        if try journals.contents(id) != nil { return try loadSession(id) }
        let header = try snapshotStore.load(id: id)
        let writer = JournalWriter(sink: try journals.create(id), nextSeq: 1, now: now)
        try writer.append(.sessionStart) { record in
            record.undoes = header.undoes
            record.reason = "adopted from snapshot header"
        }
        var seen: Set<String> = []
        for (offset, change) in header.changes.enumerated() where seen.insert(change.id).inserted {
            guard let setting = try? registry.setting(change.id) else { continue }
            let prior = change.prior ?? change.from.map { PriorState(state: .explicit, value: written($0, for: setting)) }
                ?? PriorState(state: .absent)
            try writer.append(.intent) { record in
                record.index = offset + 1
                record.settingID = setting.id
                Self.fillKey(&record, setting)
                record.prior = prior
                record.new = change.new ?? RecordedValue(absent: nil, value: written(change.to, for: setting),
                                                         type: nil, hmac: nil)
                record.wallpapers = change.wallpaperBefore
                record.after = setting.after.map(Self.effectName)
            }
        }
        return try loadSession(id)
    }

    fileprivate static func fillKey(_ record: inout JournalRecord, _ setting: Setting) {
        if case .defaults(let domain, let key, _) = setting.backend {
            record.domain = domain
            record.key = key
            record.host = setting.scope
        }
    }

    fileprivate func appender(for session: Session) throws -> JournalWriter {
        guard let sink = try journals.openForAppend(session.id) else { throw MacCtlError.snapshotNotFound(session.id) }
        return JournalWriter(sink: sink, nextSeq: session.nextSeq, now: now)
    }

    /// ADR D2 write order:
    /// header (written once) [H1] session_start [K1]; per change i: [Ii.1] intent [Ii.2] F_FULLFSYNC
    /// [Ii.3] write [Wi.1] synchronize [Wi.2] read-back [Ai.1] applied + F_FULLFSYNC [Ai.2];
    /// then [K2] restarts [E1] session_end{completed} [K3].
    /// A write that throws or reads back differently: [Fi.1] failed [Fi.2], then roll back i..1 at once
    /// (RIj/RVj), restarts, [E1] session_end{rolled_back} [K3], and `mutation_failed`.
    fileprivate func runSession(_ planned: [Planned], undoes: String?) async throws -> (id: String, notes: [String]) {
        let date = now()
        let existing = Set(try journals.ids()).union(try snapshotStore.list().map(\.id))
        let id = FileSnapshotStore.makeID(date: date, existing: existing)
        try snapshotStore.save(Snapshot(id: id, createdAt: date, changes: planned.map(\.change), undoes: undoes, status: .pending))
        Failpoint.hit("H1")
        let writer = JournalWriter(sink: try journals.create(id), nextSeq: 1, now: now)
        try writer.append(.sessionStart, points: (nil, "K1")) { $0.undoes = undoes }
        let key = { try journals.hmacKey() }

        for (offset, item) in planned.enumerated() {
            let i = offset + 1
            let setting = item.setting
            Failpoint.hit("I\(i).1")
            let seq = try writer.append(.intent, points: ("I\(i).2", "I\(i).3")) { record in
                record.index = i
                record.settingID = setting.id
                Self.fillKey(&record, setting)
                record.prior = item.change.prior
                record.new = item.change.new
                record.wallpapers = item.change.wallpaperBefore
                record.after = setting.after.map(Self.effectName)
                record.sensitive = setting.sensitive ? true : nil
            }
            var failure: String?
            var observed: RecordedValue?
            do {
                try Task.checkCancellation()
                try await Failpoint.$writePoints.withValue(("W\(i).1", "W\(i).2")) {
                    if let wallpapers = item.wallpapersTarget {
                        try await backend.restoreWallpapers(wallpapers, for: setting)
                    } else if let value = item.target {
                        try await backend.write(value, for: setting)
                    } else {
                        try await backend.reset(setting)
                    }
                }
                let current = try await backend.storedValue(setting)
                var readBack: Bool?
                if let saved = item.wallpapersTarget { readBack = try await backend.wallpapers(for: setting) == saved }
                if try !(readBack ?? (item.change.new ?? .missing).matches(current, key: key)) {
                    failure = "read-back of \(setting.id) did not match what was written"
                    observed = try RecordedValue.record(current, sensitive: setting.sensitive, key: key)
                }
            } catch {
                failure = String(describing: error)
            }
            if let failure {
                Failpoint.hit("F\(i).1")
                try writer.append(.failed, points: (nil, "F\(i).2")) { record in
                    record.ref = seq
                    record.reason = failure
                    record.observed = observed
                }
                let report: WalkReport
                do {
                    report = try await walk(try loadSession(id), writer: writer, mode: .rollback, force: false)
                } catch {
                    // The rollback stopped part-way: the session stays unresolved for `macctl recover`.
                    throw MacCtlError.mutationFailed(
                        snapshotID: id, appliedSettings: planned.prefix(i).map(\.setting.id),
                        reason: "\(failure); rolling back also failed (\(error)), run `macctl recover`")
                }
                Failpoint.hit("E1")
                try writer.append(.sessionEnd, points: (nil, "K3")) { record in
                    record.outcome = Snapshot.Status.rolledBack.rawValue
                    record.reason = failure
                }
                throw MacCtlError.mutationFailed(snapshotID: id, appliedSettings: report.flagged, reason: failure)
            }
            Failpoint.hit("A\(i).1")
            try writer.append(.applied, points: (nil, "A\(i).2")) { $0.ref = seq }
        }
        Failpoint.hit("K2")
        let restartNotes = await runRestarts(for: planned.map(\.setting))
        Failpoint.hit("E1")
        try writer.append(.sessionEnd, points: (nil, "K3")) { record in
            record.outcome = Snapshot.Status.completed.rawValue
            record.reason = restartNotes.isEmpty ? nil : restartNotes.joined(separator: " ")
        }
        return (id, restartNotes)
    }

    /// The revert walk shared by apply rollback, `undo` and `recover` (ADR D2):
    /// 1. an intent with no outcome is resolved by re-reading: = new → `applied`; = prior → `failed`
    ///    `not-applied`; a third value → `flagged`;
    /// 2. newest seq first, each applied change (and, in a rollback, the failed one) is restored:
    ///    already at prior → `reverted` with no write; changed since macctl wrote it → `revert_flagged`
    ///    (left alone unless `force`); else `revert_intent{ref, prior, expected}` + F_FULLFSYNC [RIj]
    ///    restore + synchronize [RVj] `reverted` + F_FULLFSYNC. A `revert_intent` left open by a crash is
    ///    resolved by re-reading: still `expected` → restore now; at prior → `reverted`; a third value →
    ///    `revert_flagged` (before-state not matched);
    /// 3. the restarts of the restored settings run once. The caller appends `session_end`.
    fileprivate func walk(_ session: Session, writer: JournalWriter, mode: WalkMode, force: Bool) async throws -> WalkReport {
        let key = { try journals.hmacKey() }
        var report = WalkReport()
        var outcomes = session.outcomes

        for intent in session.intents where outcomes[intent.seq] == nil {
            guard let setting = intent.settingID.flatMap({ try? registry.setting($0) }), let prior = intent.prior else {
                report.notes.append("Skipped \(intent.settingID ?? "?") in \(session.id): not in this catalog.")
                continue
            }
            let current = try await backend.storedValue(setting)
            if try (intent.new ?? .missing).matches(current, key: key) {
                try writer.append(.applied) { record in
                    record.ref = intent.seq
                    record.reason = "resolved: current value equals new"
                }
                outcomes[intent.seq] = .applied
            } else if try prior.isCurrent(current, key: key), try await wallpapersAt(intent.wallpapers, setting) {
                try writer.append(.failed) { record in
                    record.ref = intent.seq
                    record.reason = "not-applied"
                }
                outcomes[intent.seq] = .failed
                report.notApplied.append(setting.id)
            } else {
                let seen = try RecordedValue.record(current, sensitive: setting.sensitive, key: key)
                try writer.append(.flagged) { record in
                    record.ref = intent.seq
                    record.observed = seen
                    record.reason = "unknown outcome: the value is neither the prior nor the new one"
                }
                outcomes[intent.seq] = .flagged
                report.flagged.append(setting.id)
            }
        }

        let reverts = session.reverts
        let candidates = session.intents.filter { intent in
            let outcome = outcomes[intent.seq]
            let wanted = outcome == .applied || (mode == .rollback && outcome == .failed)
            switch reverts[intent.seq] {
            case .reverted: return false
            case .flagged: return wanted && force
            case .open: return true
            case nil: return wanted
            }
        }.sorted { $0.seq > $1.seq }

        for intent in candidates {
            guard let settingID = intent.settingID, let setting = try? registry.setting(settingID),
                  let prior = intent.prior else {
                report.notes.append("Skipped \(intent.settingID ?? "?") in \(session.id): not in this catalog.")
                continue
            }
            // A journal line without an index (hand-edited or another format) still recovers; it
            // just has no RIj/RVj point (Sam #62 LOW b).
            let j = intent.index.flatMap { $0 >= 1 ? $0 : nil }
            let current = try await backend.storedValue(setting)
            let seen = try RecordedValue.record(current, sensitive: setting.sensitive, key: key)
            let flag = { (reason: String) in
                try writer.append(.revertFlagged) { record in
                    record.ref = intent.seq
                    record.observed = seen
                    record.reason = reason
                }
                report.flagged.append(setting.id)
            }
            if try prior.isCurrent(current, key: key), try await wallpapersAt(intent.wallpapers, setting) {
                // A failed change still at prior was never written: nothing to revert, no line.
                if outcomes[intent.seq] == .failed, reverts[intent.seq] == nil { continue }
                // A crash at RVj (restored, `reverted` not yet written) finishes with the very line an
                // uninterrupted walk writes, so a rerun is byte-identical apart from ts/seq (ADR L133).
                let resumed: Bool
                if case .open = reverts[intent.seq] { resumed = true } else { resumed = false }
                try writer.append(.reverted) { record in
                    record.ref = intent.seq
                    if !resumed { record.reason = "already at prior" }
                }
                continue
            }
            if case .open(let open) = reverts[intent.seq] {
                // A crash after revert_intent: restore only if the key still holds what we expected.
                guard try (open.expected ?? .missing).matches(current, key: key) else {
                    try flag("before-state not matched: the value is neither the expected nor the prior one")
                    continue
                }
            } else {
                let isFailedChange = outcomes[intent.seq] == .failed
                let matchesNew = try (intent.new ?? .missing).matches(current, key: key)
                // Accepted by Max (#62 design review): a failed change whose read-back is a third value
                // (neither prior nor new) is not ours to overwrite: revert_flagged, before-state not matched.
                if isFailedChange && !matchesNew && !force {
                    try flag("before-state not matched: read-back returned a third value")
                    continue
                }
                let handEdited = !isFailedChange && !matchesNew
                if handEdited && !force {
                    try flag("changed by hand after apply")
                    continue
                }
                if !prior.isRestorable {
                    try flag("sensitive prior is stored as a hash only")
                    continue
                }
                if let reason = (intent.wallpapers?.map { Value.string($0.path) } ?? prior.value.map { [$0.value] } ?? [])
                    .compactMap({ unrestorable($0, for: setting) }).first {
                    try flag("cannot restore: \(reason)")
                    continue
                }
                try writer.append(.revertIntent) { record in
                    record.ref = intent.seq
                    record.prior = prior
                    record.expected = seen
                    record.forced = handEdited ? true : nil
                }
            }
            if let j { Failpoint.hit("RI\(j)") }
            if let wallpapers = intent.wallpapers, !wallpapers.isEmpty, prior.state == .explicit {
                try await backend.restoreWallpapers(wallpapers, for: setting)
            } else if prior.restoresByDeleting {
                try await backend.reset(setting)
            } else if let value = prior.value {
                try await backend.writeExact(value, for: setting)
            }
            if let j { Failpoint.hit("RV\(j)") }
            // D1: every restore is read back with the exact triple. A restore that did not take (dropped
            // or landed as something else) is revert_flagged with what is there, never `reverted`.
            let restored = try await backend.storedValue(setting)
            guard try prior.isCurrent(restored, key: key), try await wallpapersAt(intent.wallpapers, setting) else {
                let observed = try RecordedValue.record(restored, sensitive: setting.sensitive, key: key)
                try writer.append(.revertFlagged) { record in
                    record.ref = intent.seq
                    record.observed = observed
                    record.reason = "restore did not take"
                }
                report.flagged.append(setting.id)
                continue
            }
            try writer.append(.reverted) { $0.ref = intent.seq }
            report.reverted.append(setting)
            report.changes.append(Change(id: setting.id, from: current.map(\.value),
                                         to: prior.displayValue ?? setting.systemDefault ?? .string("(unset)")))
        }

        report.notes += await runRestarts(for: report.reverted)
        if !report.flagged.isEmpty {
            report.notes.append("Left as they are (changed after macctl wrote them): \(report.flagged.joined(separator: ", ")).")
        }
        return report
    }

    /// For wallpaper changes: whether every display shows the recorded pictures (true for others).
    private func wallpapersAt(_ saved: [DisplayWallpaper]?, _ setting: Setting) async throws -> Bool {
        guard let saved, !saved.isEmpty else { return true }
        return try await backend.wallpapers(for: setting) == saved
    }

    /// ADR D2 retention (Q3): only ended sessions with every record terminal and no flag are pruned,
    /// keeping the newest 100 or everything from the last 30 days, whichever keeps more. The header
    /// goes first, then the journal, so a crash in between leaves a complete journal and no orphan
    /// header. Pre-journal snapshots are never deleted. Runs under the lock.
    fileprivate func pruneJournals() {
        guard let ids = try? journals.ids() else { return }
        var ended: [(Date, String)] = []
        for id in ids {
            // A session that undid a pre-journal snapshot is that snapshot's only "undone" record:
            // pruning it would put the legacy snapshot back in effect for `macctl undo` (Sam #62 LOW c).
            guard let session = try? loadSession(id), !session.unresolved, session.allTerminal,
                  session.flaggedSettings.isEmpty, session.start?.undoes == nil else { continue }
            ended.append((session.createdAt, id))
        }
        ended.sort { $0.0 > $1.0 }
        let cutoff = now().addingTimeInterval(-30 * 24 * 60 * 60)
        for (offset, entry) in ended.enumerated() where offset >= 100 && entry.0 < cutoff {
            do {
                try snapshotStore.remove(id: entry.1)
                try journals.remove(entry.1)
            } catch { continue }
        }
    }
}
