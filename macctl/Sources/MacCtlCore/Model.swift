import Foundation

/// A concrete setting value. JSON encodes scalars as bare values (`true`, `40`, `0.5`, `"dark"`), so
/// older snapshots and profiles stay readable. The container and binary cases exist to record a
/// prior value of any property-list type exactly (ADR D1); the JSON for those is tagged
/// (`{"$data": base64}`, `{"$date": iso8601}`, `[...]`, `{"$dict": {...}}`). Where the exact type
/// matters (int vs real nested in an array), journals use `TypedValue`, which stores containers as
/// binary plist.
public enum Value: Sendable, Hashable, Codable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)
    case array([Value])
    case dictionary([String: Value])

    private enum TagKey: String, CodingKey {
        case data = "$data", date = "$date", dict = "$dict"
    }

    public init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            if let i = try? c.decode(Int.self) { self = .int(i); return }
            if let d = try? c.decode(Double.self) { self = .double(d); return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let a = try? c.decode([Value].self) { self = .array(a); return }
        }
        let keyed = try decoder.container(keyedBy: TagKey.self)
        if let text = try keyed.decodeIfPresent(String.self, forKey: .data) {
            guard let data = Data(base64Encoded: text) else {
                throw DecodingError.dataCorruptedError(forKey: .data, in: keyed, debugDescription: "invalid base64")
            }
            self = .data(data)
        } else if let text = try keyed.decodeIfPresent(String.self, forKey: .date) {
            guard let date = Value.iso8601(text) else {
                throw DecodingError.dataCorruptedError(forKey: .date, in: keyed, debugDescription: "invalid date")
            }
            self = .date(date)
        } else {
            self = .dictionary(try keyed.decode([String: Value].self, forKey: .dict))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .bool(let b): var c = encoder.singleValueContainer(); try c.encode(b)
        case .int(let i): var c = encoder.singleValueContainer(); try c.encode(i)
        case .double(let d): var c = encoder.singleValueContainer(); try c.encode(d)
        case .string(let s): var c = encoder.singleValueContainer(); try c.encode(s)
        case .array(let a): var c = encoder.singleValueContainer(); try c.encode(a)
        case .data(let d):
            var c = encoder.container(keyedBy: TagKey.self); try c.encode(d.base64EncodedString(), forKey: .data)
        case .date(let d):
            var c = encoder.container(keyedBy: TagKey.self); try c.encode(Value.iso8601(d), forKey: .date)
        case .dictionary(let d):
            var c = encoder.container(keyedBy: TagKey.self); try c.encode(d, forKey: .dict)
        }
    }

    public var description: String {
        switch self {
        case .bool(let b): String(b)
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .string(let s): s
        case .data(let d): "<\(d.count) bytes>"
        case .date(let d): Value.iso8601(d)
        case .array(let a): "[" + a.map(\.description).joined(separator: ", ") + "]"
        case .dictionary(let d):
            "{" + d.keys.sorted().map { "\($0): \(d[$0]!.description)" }.joined(separator: ", ") + "}"
        }
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func iso8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// What values a setting accepts. Used to parse CLI text and validate profile values.
public enum ValueType: Sendable, Hashable {
    case bool
    case int(min: Int?, max: Int?)
    case double(min: Double?, max: Double?)
    case string
    case enumeration([String])
    /// A filesystem path; `~` is expanded before writing.
    case path
}

public enum Risk: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case read, user, admin, destructive

    public static func < (a: Risk, b: Risk) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

public enum Permission: Sendable, Hashable {
    /// Apple Events to the app with this bundle id (for example `com.apple.systemevents`).
    case automation(bundleID: String)
    case accessibility
    case fullDiskAccess
}

/// What must happen after a write for it to take effect. `apply` batches these and runs each once.
public enum SideEffect: Sendable, Hashable {
    /// `killall <process>` (Dock, Finder, SystemUIServer).
    case restart(process: String)
    case logout
}

/// How `defaults` stores the value (`-bool`, `-int`, `-float`, `-string`).
public enum DefaultsType: String, Sendable, Hashable {
    case bool, int, float, string
}

/// How a setting is read and written. Scripts are fixed text; values only ever arrive as argv.
public enum Backend: Sendable, Hashable {
    /// `domain` is a preferences domain such as `com.apple.dock`; use `Backend.globalDomain` for `-g`.
    case defaults(domain: String, key: String, type: DefaultsType)
    /// `get` prints the current value; `set` receives the new value as `item 1 of argv` (`on run argv`).
    case appleScript(get: String, set: String)
    /// The desktop picture through `NSWorkspace`: read = main screen, write = every screen.
    case wallpaper

    public static let globalDomain = "NSGlobalDomain"
}

/// One configurable thing in the catalog.
public struct Setting: Sendable, Hashable, Identifiable {
    /// Dotted id, `<domain>.<name>`, lowercase kebab: `dock.autohide`, `finder.show-extensions`.
    public let id: String
    /// One line an agent can read to understand the setting.
    public let summary: String
    public let type: ValueType
    public let risk: Risk
    public let permissions: [Permission]
    public let backend: Backend
    public let after: [SideEffect]
    /// macOS default, reported when the key is unset.
    public let systemDefault: Value?
    /// macOS versions a human verified this setting on (for example `"26.0"`). Empty = unverified.
    public let verifiedOn: [String]
    /// Host scope of a `.defaults` key: anyHost (`defaults write`) or currentHost (`-currentHost`).
    public let scope: PreferenceHost
    /// Journals store only a keyed hash of this setting's values, never the value (ADR D2 Privacy).
    public let sensitive: Bool

    public init(
        id: String, summary: String, type: ValueType, risk: Risk = .user,
        permissions: [Permission] = [], backend: Backend, after: [SideEffect] = [],
        systemDefault: Value? = nil, verifiedOn: [String] = [],
        scope: PreferenceHost = .anyHost, sensitive: Bool = false
    ) {
        self.scope = scope
        self.sensitive = sensitive
        self.id = id
        self.summary = summary
        self.type = type
        self.risk = risk
        self.permissions = permissions
        self.backend = backend
        self.after = after
        self.systemDefault = systemDefault
        self.verifiedOn = verifiedOn
    }

    /// The part of the id before the first dot (`dock`).
    public var domain: String { String(id.prefix { $0 != "." }) }
}

/// A desired-state file. `settings` maps setting id to value.
public struct Profile: Sendable, Hashable, Codable {
    public var name: String
    public var version: Int
    public var settings: [String: Value]

    public init(name: String, version: Int = 1, settings: [String: Value]) {
        self.name = name
        self.version = version
        self.settings = settings
    }
}

/// One planned or applied change. `from == nil` means the key was unset (undo deletes it).
///
/// `prior` and `new` (ADR D1/D2) are the exact typed record undo restores from and compares with;
/// `from`/`to` stay the catalog-typed scalars older clients (Summon) read. Snapshots without `prior`
/// are legacy and restore through `from`.
public struct Change: Sendable, Hashable, Codable {
    public let id: String
    public let from: Value?
    public let to: Value
    /// Optional restoration metadata. Scalars remain readable by older clients and snapshots.
    public let wallpaperBefore: [DisplayWallpaper]?
    public let wallpaperAfter: [DisplayWallpaper]?
    public let prior: PriorState?
    public let new: RecordedValue?

    public init(id: String, from: Value?, to: Value,
                wallpaperBefore: [DisplayWallpaper]? = nil, wallpaperAfter: [DisplayWallpaper]? = nil,
                prior: PriorState? = nil, new: RecordedValue? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.wallpaperBefore = wallpaperBefore
        self.wallpaperAfter = wallpaperAfter
        self.prior = prior
        self.new = new
    }
}

/// A session as `snapshot list` shows it. For journaled sessions, `snapshots/<id>.json` is a
/// write-once header saved with status `pending` and never rewritten; the status shown is derived
/// from the journal (ADR D2, Q-H). Pre-journal snapshots carry their own status.
public struct Snapshot: Sendable, Hashable, Codable, Identifiable {
    /// Journaled outcomes: `completed`; `rolled_back` (a failed apply undone at once); `undone`
    /// (reverted by `macctl undo`); `recovered` (rolled back by `macctl recover`, QA R-b).
    /// `pending`: unfinished. `failed`: pre-journal snapshots only.
    public enum Status: String, Sendable, Hashable, Codable {
        case pending, completed, failed, recovered
        case rolledBack = "rolled_back"
        case undone
    }
    /// Sortable timestamp id, `yyyyMMdd-HHmmss`.
    public let id: String
    public let createdAt: Date
    public let changes: [Change]
    /// Set on the snapshot an `undo` records: the id of the snapshot it reverted.
    public let undoes: String?
    /// Missing on legacy snapshots, which represent completed operations.
    public let status: Status?
    public let appliedSettings: [String]?
    public let failure: String?
    public var completed: Bool { status == nil || status == .completed }
    /// Pending or failed: blocks new mutations until `macctl recover` (ADR Q4).
    public var unresolved: Bool { status == .pending || status == .failed }

    public init(id: String, createdAt: Date, changes: [Change], undoes: String? = nil,
                status: Status? = nil, appliedSettings: [String]? = nil, failure: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.changes = changes
        self.undoes = undoes
        self.status = status
        self.appliedSettings = appliedSettings
        self.failure = failure
    }
}

/// ADR D1: what a key held before macctl changed it.
///
/// - `absent`: no value anywhere; restore deletes the explicit key.
/// - `explicit`: this exact `(appID, user, host)` triple held `value` (exact type); restore writes it back.
/// - `inherited`: no explicit value, but one came from another layer (`layer`: `global`, `otherHost`
///   or `unknown`). `value` is for display; restore deletes so inheritance resumes.
///
/// `defaults delete` is never the inverse of a write to a key that existed: that would drop the
/// effective value to another layer and lose the original type.
public struct PriorState: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable { case absent, explicit, inherited }

    public let state: Kind
    /// The exact prior (explicit) or the inherited value (display only). Nil for sensitive settings.
    public let value: TypedValue?
    /// Sensitive settings: `type` plus `hmac` (HMAC-SHA256 with the per-install key) instead of `value`.
    public let type: PlistType?
    public let hmac: String?
    public let host: PreferenceHost?
    public let layer: String?
    /// A currentHost value that shadows the anyHost key being written (the write has no visible effect).
    public let shadowedBy: PreferenceHost?

    public init(state: Kind, value: TypedValue? = nil, host: PreferenceHost? = nil, layer: String? = nil,
                shadowedBy: PreferenceHost? = nil, type: PlistType? = nil, hmac: String? = nil) {
        self.state = state
        self.value = value
        self.type = type ?? value?.type
        self.hmac = hmac
        self.host = host
        self.layer = layer
        self.shadowedBy = shadowedBy
    }

    static func explicitOrAbsent(_ value: Value?) -> PriorState {
        value.map { PriorState(state: .explicit, value: TypedValue($0)) } ?? PriorState(state: .absent)
    }

    /// Restoring deletes (absent, inherited) or writes `value` back (explicit).
    public var restoresByDeleting: Bool { state != .explicit }
}
