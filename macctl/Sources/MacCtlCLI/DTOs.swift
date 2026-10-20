import Foundation
import MacCtlCore

// JSON shapes the CLI prints. Core types that are not Codable are flattened to strings here.

/// A value type as JSON: `{"kind": "int", "min": 16, "max": 128}` or `{"kind": "enum", "values": [...]}`.
struct TypeInfo: Encodable {
    let kind: String
    let min: Value?
    let max: Value?
    let values: [String]?

    init(_ type: ValueType) {
        var lower: Value? = nil
        var upper: Value? = nil
        var options: [String]? = nil
        let name: String
        switch type {
        case .bool:
            name = "bool"
        case .int(let lo, let hi):
            name = "int"
            if let lo { lower = .int(lo) }
            if let hi { upper = .int(hi) }
        case .double(let lo, let hi):
            name = "double"
            if let lo { lower = .double(lo) }
            if let hi { upper = .double(hi) }
        case .string:
            name = "string"
        case .enumeration(let list):
            name = "enum"
            options = list
        case .path:
            name = "path"
        }
        kind = name
        min = lower
        max = upper
        values = options
    }

    /// `bool`, `int 16...128`, `enum left|bottom|right`.
    var text: String {
        if let values { return values.joined(separator: "|") }
        switch (min, max) {
        case (nil, nil): return kind
        case let (lo, hi): return "\(kind) \(lo?.description ?? "")...\(hi?.description ?? "")"
        }
    }
}

/// One catalog entry, as `list`, `describe` and `get` report it.
struct SettingInfo: Encodable {
    let id: String
    let domain: String
    let summary: String
    let type: TypeInfo
    let risk: Risk
    let permissions: [String]
    let sideEffects: [String]
    let backend: String
    let verified: Bool
    let verifiedOn: [String]
    let systemDefault: Value?
    /// Effective value; nil when unset with no known default, or when reading failed.
    let current: Value?
    /// Why `current` could not be read (for example a missing permission).
    let currentError: String?

    init(_ setting: Setting, current: Value?, currentError: String? = nil) {
        id = setting.id
        domain = setting.domain
        summary = setting.summary
        type = TypeInfo(setting.type)
        risk = setting.risk
        permissions = setting.permissions.map(Self.permissionName)
        sideEffects = setting.after.map(Self.sideEffectName)
        backend = Self.backendName(setting.backend)
        verified = !setting.verifiedOn.isEmpty
        verifiedOn = setting.verifiedOn
        systemDefault = setting.systemDefault
        self.current = current
        self.currentError = currentError
    }

    /// Reads the current value without failing the whole command.
    static func load(_ setting: Setting, from service: any MacCtlService) async -> SettingInfo {
        do {
            return SettingInfo(setting, current: try await service.get(setting.id))
        } catch let error as MacCtlError {
            return SettingInfo(setting, current: nil, currentError: error.description)
        } catch {
            return SettingInfo(setting, current: nil, currentError: String(describing: error))
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, domain, summary, type, risk, permissions, sideEffects, backend
        case verified, verifiedOn, systemDefault, current, currentError
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(domain, forKey: .domain)
        try c.encode(summary, forKey: .summary)
        try c.encode(type, forKey: .type)
        try c.encode(risk, forKey: .risk)
        try c.encode(permissions, forKey: .permissions)
        try c.encode(sideEffects, forKey: .sideEffects)
        try c.encode(backend, forKey: .backend)
        try c.encode(verified, forKey: .verified)
        try c.encode(verifiedOn, forKey: .verifiedOn)
        // Always present, `null` when unknown, so agents can rely on the keys.
        try c.encode(systemDefault, forKey: .systemDefault)
        try c.encode(current, forKey: .current)
        try c.encodeIfPresent(currentError, forKey: .currentError)
    }

    static func permissionName(_ permission: Permission) -> String {
        switch permission {
        case .automation(let bundleID): "automation:\(bundleID)"
        case .accessibility: "accessibility"
        case .fullDiskAccess: "full-disk-access"
        }
    }

    static func sideEffectName(_ effect: SideEffect) -> String {
        switch effect {
        case .restart(let process): "restart:\(process)"
        case .logout: "logout"
        }
    }

    static func backendName(_ backend: Backend) -> String {
        switch backend {
        case .defaults(let domain, let key, let type):
            let target = domain == Backend.globalDomain ? "-g" : domain
            return "defaults \(target) \(key) -\(type.rawValue)"
        case .appleScript:
            return "applescript"
        case .wallpaper:
            return "nsworkspace desktop image"
        }
    }
}

/// One `get` result. `value` is `null` when unset with no known default.
struct SettingValue: Encodable {
    let id: String
    let value: Value?

    enum CodingKeys: String, CodingKey { case id, value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(value, forKey: .value)
    }
}

struct DiffResult: Encodable {
    let profile: String
    let changes: [Change]
}

struct SnapshotSummary: Encodable {
    let id: String
    let createdAt: Date
    let changeCount: Int
    let settings: [String]
    let status: Snapshot.Status?
    let undoes: String?
    let appliedSettings: [String]?
    let failure: String?

    init(_ snapshot: Snapshot) {
        id = snapshot.id
        createdAt = snapshot.createdAt
        changeCount = snapshot.changes.count
        settings = snapshot.changes.map(\.id)
        status = snapshot.status
        undoes = snapshot.undoes
        appliedSettings = snapshot.appliedSettings
        failure = snapshot.failure
    }
}
