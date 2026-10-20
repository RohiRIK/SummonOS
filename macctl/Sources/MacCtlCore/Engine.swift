import Foundation

/// The one implementation of `MacCtlService`: validates, plans, snapshots, writes, restarts, undoes.
///
/// Every operation validates input before its first write. Runtime failures preserve a recovery
/// journal and report completed writes; operations are serialized across the snapshot store.
public struct Engine: MacCtlService {
    public let registry: Registry
    private let backend: any SettingBackend
    private let restarter: any Restarter
    private let probe: any PermissionProbe
    private let snapshotStore: any SnapshotStore
    private let osVersion: @Sendable () async -> String
    private let now: @Sendable () -> Date

    public init(
        registry: Registry,
        backend: any SettingBackend,
        restarter: any Restarter,
        probe: any PermissionProbe,
        snapshots: any SnapshotStore,
        osVersion: @escaping @Sendable () async -> String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.registry = registry
        self.backend = backend
        self.restarter = restarter
        self.probe = probe
        self.snapshotStore = snapshots
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
        return try await backend.read(setting) ?? setting.systemDefault.map(setting.type.normalize)
    }

    public func parse(_ text: String, for id: String) throws -> Value {
        let setting = try registry.setting(id)
        return try setting.type.parse(text, id: id)
    }

    // MARK: - Diff / apply

    /// `Change.from` is the stored value (nil = unset, the system default applies), matching the
    /// snapshot semantics; a setting is listed only when its effective value differs from the target.
    public func diff(_ profile: Profile) async throws -> [Change] {
        let targets = try resolve(profile)
        try await requirePermissions(targets.map(\.setting))
        return try await plan(targets).map(\.change)
    }

    public func apply(_ profile: Profile, dryRun: Bool, confirmed: Bool) async throws -> ApplyResult {
        let transaction = dryRun ? nil : try await snapshotStore.acquireTransaction()
        defer { transaction?.release() }
        if !dryRun { Failpoint.hit("lock.acquired") }
        let targets = try resolve(profile)
        try await requirePermissions(targets.map(\.setting))
        let planned = try await plan(targets)
        if !dryRun { Failpoint.hit("plan.done") }

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
        let notes = lost + Self.notes(for: planned.map(\.setting))
        guard !dryRun, !planned.isEmpty else {
            return ApplyResult(snapshotID: nil, changes: changes, dryRun: dryRun, notes: notes)
        }

        let snapshot = try saveSnapshot(changes)
        try await write(planned.map { WriteStep(setting: $0.setting, value: $0.change.to) }, snapshot: snapshot)
        return ApplyResult(snapshotID: snapshot.id, changes: changes, dryRun: false, notes: notes)
    }

    // MARK: - Snapshots / undo

    public func snapshots() throws -> [Snapshot] {
        try snapshotStore.list()
    }

    /// Restores `from` for each change of the snapshot, in reverse order; `from == nil` resets the key.
    /// The undo itself is snapshotted first (marked `undoes`), so it can be undone by id.
    /// Without an id, picks the newest change that is not an undo and was not undone yet, so repeated
    /// `undo` steps further back instead of toggling.
    public func undo(snapshotID: String?) async throws -> ApplyResult {
        let transaction = try await snapshotStore.acquireTransaction()
        defer { transaction.release() }
        let snapshot: Snapshot
        if let snapshotID {
            snapshot = try snapshotStore.load(id: snapshotID)
        } else {
            let all = try snapshotStore.list()
            let undone = Set(all.filter(\.completed).compactMap(\.undoes))
            guard let newest = all.first(where: { $0.undoes == nil && !undone.contains($0.id) }) else {
                throw MacCtlError.noSnapshots
            }
            snapshot = newest
        }

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

        var steps: [WriteStep] = []
        var undoChanges: [Change] = []
        for entry in entries {
            let current = try await backend.read(entry.setting)
            if let saved = entry.wallpapers {
                let currentDisplays = try await backend.wallpapers(for: entry.setting)
                if currentDisplays == saved { continue }
                guard let restoredValue = entry.restore ?? saved.first.map({ Value.string($0.path) }) else {
                    throw MacCtlError.invalidProfile("snapshot has no saved wallpaper value for \(entry.setting.id)")
                }
                steps.append(WriteStep(setting: entry.setting, value: entry.restore, wallpapers: saved))
                undoChanges.append(Change(id: entry.setting.id, from: current,
                                          to: restoredValue,
                                          wallpaperBefore: currentDisplays, wallpaperAfter: saved))
            } else if let restore = entry.restore {
                let value = entry.setting.type.normalize(restore)
                if let current, current.sameValue(as: value) { continue }
                steps.append(WriteStep(setting: entry.setting, value: value))
                undoChanges.append(Change(id: entry.setting.id, from: current, to: value,
                                          wallpaperBefore: try await backend.wallpapers(for: entry.setting)))
            } else {
                // Was unset: delete the key. Nothing to do when it is already unset.
                guard let current else { continue }
                steps.append(WriteStep(setting: entry.setting, value: nil))
                undoChanges.append(
                    Change(id: entry.setting.id, from: current, to: entry.setting.systemDefault ?? current))
            }
        }

        // A value that can no longer be written (the old wallpaper file was deleted) is skipped with
        // a note, so it neither blocks the rest of the undo nor every later `undo`.
        var skipped: [String] = []
        for (index, step) in steps.enumerated().reversed() {
            let values = step.wallpapers?.map { Value.string($0.path) } ?? step.value.map { [$0] } ?? []
            guard let reason = values.compactMap({ unrestorable($0, for: step.setting) }).first else { continue }
            steps.remove(at: index)
            undoChanges.remove(at: index)
            skipped.insert("Could not restore \(step.setting.id): \(reason). Left as is.", at: 0)
        }

        let notes = skipped + Self.notes(for: steps.map { $0.setting })
        // Record a completed no-op too: an already-restored snapshot must not block older history.
        let undoSnapshot = try saveSnapshot(undoChanges, undoes: snapshot.id)
        try await write(steps, snapshot: undoSnapshot)
        return ApplyResult(snapshotID: undoSnapshot.id, changes: undoChanges, dryRun: false, notes: notes)
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

        return DoctorReport(macOSVersion: version, checks: checks)
    }

    // MARK: - Private

    private struct Target {
        let setting: Setting
        let value: Value
    }

    private struct Planned {
        let setting: Setting
        let change: Change
    }

    private struct WriteStep {
        let setting: Setting
        let value: Value?
        var wallpapers: [DisplayWallpaper]? = nil
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

    /// Reads stored values; keeps only targets whose effective value (stored, else system default) differs.
    private func plan(_ targets: [Target]) async throws -> [Planned] {
        var planned: [Planned] = []
        for target in targets {
            let stored = try await backend.read(target.setting)
            let wallpapers = try await backend.wallpapers(for: target.setting)
            let effective = stored ?? target.setting.systemDefault.map(target.setting.type.normalize)
            let allDisplaysMatch = wallpapers?.allSatisfy { Value.string($0.path).sameValue(as: target.value) } ?? true
            if let effective, effective.sameValue(as: target.value), allDisplaysMatch { continue }
            planned.append(Planned(setting: target.setting, change: Change(id: target.setting.id, from: stored,
                                                                         to: target.value, wallpaperBefore: wallpapers)))
        }
        return planned
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

    private func saveSnapshot(_ changes: [Change], undoes: String? = nil) throws -> Snapshot {
        let date = now()
        let existing = try Set(snapshotStore.list().map(\.id))
        let snapshot = Snapshot(
            id: FileSnapshotStore.makeID(date: date, existing: existing), createdAt: date, changes: changes,
            undoes: undoes, status: .pending)
        try snapshotStore.save(snapshot)
        return snapshot
    }

    /// Writes (value) or resets (nil) each setting in order, then runs the restarts of the settings
    /// written, once each. If a write fails, the restarts for what was already written still run.
    private func write(_ steps: [WriteStep], snapshot: Snapshot) async throws {
        var written: [Setting] = []
        var restartsStarted = false
        do {
            for step in steps {
                try Task.checkCancellation()
                if let wallpapers = step.wallpapers {
                    try await backend.restoreWallpapers(wallpapers, for: step.setting)
                } else if let value = step.value {
                    try await backend.write(value, for: step.setting)
                } else {
                    try await backend.reset(step.setting)
                }
                Failpoint.hit("change.written")
                written.append(step.setting)
                try snapshotStore.update(snapshot.recording(.pending, applied: written.map(\.id)))
            }
            restartsStarted = true
            Failpoint.hit("restarts.before")
            try await runRestarts(for: written)
            Failpoint.hit("restarts.after")
            try snapshotStore.update(snapshot.recording(.completed, applied: written.map(\.id)))
        } catch {
            if !restartsStarted { try? await runRestarts(for: written) }
            var reason = String(describing: error)
            do {
                try snapshotStore.update(snapshot.recording(.failed, applied: written.map(\.id), failure: reason))
            } catch {
                reason += "; outcome could not be saved: \(error)"
            }
            throw MacCtlError.mutationFailed(snapshotID: snapshot.id, appliedSettings: written.map(\.id), reason: reason)
        }
    }

    /// `.logout` cannot be performed for the user; it becomes a note instead.
    private func runRestarts(for settings: [Setting]) async throws {
        var effects: Set<SideEffect> = []
        for setting in settings {
            for effect in setting.after {
                if case .restart = effect { effects.insert(effect) }
            }
        }
        guard !effects.isEmpty else { return }
        try await restarter.run(effects)
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
