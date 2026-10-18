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
}

extension SettingBackend {
    public func validate(_ value: Value, for setting: Setting) throws {}
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
    func save(_ snapshot: Snapshot) throws
    /// Newest first.
    func list() throws -> [Snapshot]
    func load(id: String) throws -> Snapshot
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
    func doctor() async -> DoctorReport
}
