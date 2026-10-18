import Foundation

/// A concrete setting value. JSON encodes as a bare scalar (`true`, `40`, `0.5`, `"dark"`).
public enum Value: Sendable, Hashable, Codable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        self = .string(try c.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        }
    }

    public var description: String {
        switch self {
        case .bool(let b): String(b)
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .string(let s): s
        }
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

    public init(
        id: String, summary: String, type: ValueType, risk: Risk = .user,
        permissions: [Permission] = [], backend: Backend, after: [SideEffect] = [],
        systemDefault: Value? = nil, verifiedOn: [String] = []
    ) {
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
public struct Change: Sendable, Hashable, Codable {
    public let id: String
    public let from: Value?
    public let to: Value

    public init(id: String, from: Value?, to: Value) {
        self.id = id
        self.from = from
        self.to = to
    }
}

/// Old values recorded before an apply, so `undo` can restore them.
public struct Snapshot: Sendable, Hashable, Codable, Identifiable {
    /// Sortable timestamp id, `yyyyMMdd-HHmmss`.
    public let id: String
    public let createdAt: Date
    public let changes: [Change]
    /// Set on the snapshot an `undo` records: the id of the snapshot it reverted.
    public let undoes: String?

    public init(id: String, createdAt: Date, changes: [Change], undoes: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.changes = changes
        self.undoes = undoes
    }
}
