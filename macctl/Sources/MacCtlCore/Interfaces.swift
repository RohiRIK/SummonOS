import Foundation

// Contracts between modules. Implementations live in their own files; keep these signatures stable.

/// Reads and writes one setting through its `Backend`.
public protocol SettingBackend: Sendable {
    /// Current stored value, or nil when the key is unset (the system default applies).
    func read(_ setting: Setting) async throws -> Value?
    func write(_ value: Value, for setting: Setting) async throws
    /// Remove the stored value so the system default applies again (`defaults delete`).
    func reset(_ setting: Setting) async throws
    /// Checks a value against the live system before any write (for example that a file exists).
    /// The engine calls it for every value of a batch before the first write. Default: accepts all.
    func validate(_ value: Value, for setting: Setting) throws
    func wallpapers(for setting: Setting) async throws -> [DisplayWallpaper]?
    func restoreWallpapers(_ wallpapers: [DisplayWallpaper], for setting: Setting) async throws
    /// ADR D1 prior state: absent, explicit (exact typed value) or inherited (domain default).
    /// Throws `managed_setting` for a forced key. Default: `read` as explicit or absent.
    func priorState(_ setting: Setting) async throws -> PriorState
    /// The exact stored value (type and value), for read-back and the hand-edit check.
    func storedValue(_ setting: Setting) async throws -> TypedValue?
    /// Writes back an exact typed value (restoring an explicit prior). Default: `write(value.value)`.
    func writeExact(_ value: TypedValue, for setting: Setting) async throws
}

extension SettingBackend {
    public func priorState(_ setting: Setting) async throws -> PriorState {
        try await PriorState.explicitOrAbsent(read(setting))
    }
    public func storedValue(_ setting: Setting) async throws -> TypedValue? {
        try await read(setting).map(TypedValue.init)
    }
    public func writeExact(_ value: TypedValue, for setting: Setting) async throws {
        try await write(value.value, for: setting)
    }
    public func validate(_ value: Value, for setting: Setting) throws {}
    public func wallpapers(for setting: Setting) async throws -> [DisplayWallpaper]? { nil }
    public func restoreWallpapers(_ wallpapers: [DisplayWallpaper], for setting: Setting) async throws {
        throw MacCtlError.unsupported(id: setting.id, reason: "per-display restoration is unavailable")
    }
}

/// Runs side effects (killall Dock, ...) once each, after a batch of writes.
public protocol Restarter: Sendable {
    func run(_ effects: Set<SideEffect>) async throws
}

/// Checks permissions without ever showing a prompt.
public protocol PermissionProbe: Sendable {
    func isGranted(_ permission: Permission) async -> Bool
    /// `x-apple.systempreferences:` link to the pane where the user grants it.
    func settingsURL(for permission: Permission) -> String
}

/// Persists snapshots (default: `~/Library/Application Support/macctl/snapshots/<id>.json`).
public protocol SnapshotStore: Sendable {
    /// Creates a backup. Filesystem implementations must refuse to replace an existing id.
    func save(_ snapshot: Snapshot) throws
    /// Newest first.
    func list() throws -> [Snapshot]
    func load(id: String) throws -> Snapshot
    /// Deletes a header (retention only; a header is never rewritten).
    func remove(id: String) throws
    /// Held across planning, durable backup, mutation and outcome recording.
    func acquireTransaction() async throws -> TransactionLease
}

extension SnapshotStore {
    public func acquireTransaction() async throws -> TransactionLease {
        try await InProcessTransactionLock.shared.acquire()
    }
}

/// Result of an apply. `changes` empty means the machine already matched.
public struct ApplyResult: Sendable, Hashable, Codable {
    public let snapshotID: String?
    public let changes: [Change]
    public let dryRun: Bool
    /// Human notes such as "Log out for keyboard changes to apply".
    public let notes: [String]

    public init(snapshotID: String?, changes: [Change], dryRun: Bool, notes: [String] = []) {
        self.snapshotID = snapshotID
        self.changes = changes
        self.dryRun = dryRun
        self.notes = notes
    }
}

/// Report for `macctl doctor`.
public struct DoctorReport: Sendable, Hashable, Codable {
    public struct Check: Sendable, Hashable, Codable {
        public let name: String
        public let ok: Bool
        public let detail: String
        /// Where to fix it, when not ok.
        public let fixURL: String?

        public init(name: String, ok: Bool, detail: String, fixURL: String? = nil) {
            self.name = name
            self.ok = ok
            self.detail = detail
            self.fixURL = fixURL
        }
    }

    public let macOSVersion: String
    public let checks: [Check]

    public init(macOSVersion: String, checks: [Check]) {
        self.macOSVersion = macOSVersion
        self.checks = checks
    }
}

/// Everything the CLI and (later) the MCP server call. `Engine` implements it.
public protocol MacCtlService: Sendable {
    var settings: [Setting] { get }
    func setting(_ id: String) throws -> Setting
    /// Effective value: stored value, else `systemDefault`, else nil.
    func get(_ id: String) async throws -> Value?
    /// Parse CLI text into a typed value for this setting (validates range / enum).
    func parse(_ text: String, for id: String) throws -> Value
    /// What `apply` would change; only settings whose effective value differs.
    func diff(_ profile: Profile) async throws -> [Change]
    /// Applies a profile (or a one-setting profile for `set`). Snapshots first unless dryRun.
    /// Throws `needsConfirmation` for admin/destructive settings unless `confirmed`.
    func apply(_ profile: Profile, dryRun: Bool, confirmed: Bool) async throws -> ApplyResult
    func snapshots() throws -> [Snapshot]
    /// Restores a snapshot (newest when id is nil). Returns the changes made.
    func undo(snapshotID: String?) async throws -> ApplyResult
    /// Like `undo(snapshotID:)`; `force` also overwrites keys changed by hand (ADR Q1).
    func undo(snapshotID: String?, force: Bool) async throws -> ApplyResult
    /// Rolls back every unfinished operation (ADR D2). `abandon` sets one corrupt journal aside.
    func recover(force: Bool, abandon: String?) async throws -> RecoverResult
    func doctor() async -> DoctorReport
}
