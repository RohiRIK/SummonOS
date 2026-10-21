import Foundation

/// Test wiring for the CLI, honoured only with `MACCTL_TEST_MODE=1` (QA plan 2.2):
///
/// - `MACCTL_SNAPSHOT_DIR=<dir>`: snapshots there; the journal goes to `<dir>/../journal`.
/// - `MACCTL_TEST_CATALOG=<json>`: the only settings available. Refused unless every setting is a
///   `defaults` key in a domain starting with `com.summonos.test.` (throwaway domains, `com.summonos.test.<uuid>` in tests).
/// - `MACCTL_FAKE_DEFAULTS=<dir>`: a type-preserving plist store instead of CFPreferences (Linux).
///
/// Restart effects never run in test mode. Both the snapshot directory and the catalog are
/// required, so test mode can never write the real snapshot history or a real Apple domain.
/// Setting any of these variables without `MACCTL_TEST_MODE=1` is refused rather than ignored.
public enum TestMode {
    public static let domainPrefix = "com.summonos.test."
    static let variables = ["MACCTL_SNAPSHOT_DIR", "MACCTL_TEST_CATALOG", "MACCTL_FAKE_DEFAULTS", "MACCTL_FAILPOINT"]

    public struct Configuration: Sendable {
        public let snapshotDirectory: URL
        public let settings: [Setting]
        public let fakeDefaults: URL?
    }

    /// nil = normal operation. Throws `invalid_test_mode` for any partial or unsafe configuration.
    public static func configuration(_ environment: [String: String]) throws -> Configuration? {
        let enabled = environment["MACCTL_TEST_MODE"] == "1"
        let present = variables.filter { !(environment[$0] ?? "").isEmpty }
        guard enabled else {
            if let name = present.first {
                throw MacCtlError.invalidTestMode("\(name) is set but MACCTL_TEST_MODE=1 is not; refusing to guess")
            }
            if let mode = environment["MACCTL_TEST_MODE"], !mode.isEmpty {
                throw MacCtlError.invalidTestMode("MACCTL_TEST_MODE must be 1 or unset")
            }
            return nil
        }
        guard let snapshots = environment["MACCTL_SNAPSHOT_DIR"], snapshots.hasPrefix("/") else {
            throw MacCtlError.invalidTestMode("test mode needs an absolute MACCTL_SNAPSHOT_DIR")
        }
        guard let catalog = environment["MACCTL_TEST_CATALOG"], !catalog.isEmpty else {
            throw MacCtlError.invalidTestMode("test mode needs MACCTL_TEST_CATALOG")
        }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: catalog)) } catch {
            throw MacCtlError.invalidTestMode("cannot read MACCTL_TEST_CATALOG \(catalog)")
        }
        let fake = environment["MACCTL_FAKE_DEFAULTS"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        return Configuration(snapshotDirectory: URL(fileURLWithPath: snapshots, isDirectory: true),
                             settings: try parseCatalog(data), fakeDefaults: fake)
    }

    struct Entry: Decodable {
        struct Defaults: Decodable {
            let domain: String
            let key: String
            let type: String
            let host: PreferenceHost?
        }
        struct BackendSpec: Decodable {
            let defaults: Defaults?
            let appleScript: AnyCodable?
            let wallpaper: AnyCodable?
        }
        let id: String
        let type: String
        let backend: BackendSpec
        let after: [String]?
        let systemDefault: Value?
        let sensitive: Bool?
        let risk: Risk?
    }

    struct AnyCodable: Decodable {
        init(from decoder: Decoder) throws {}
    }

    struct Wrapped: Decodable { let settings: [Entry] }

    /// Accepts `[entry, ...]` or `{"settings": [entry, ...]}`.
    public static func parseCatalog(_ data: Data) throws -> [Setting] {
        let decoder = JSONDecoder()
        let entries: [Entry]
        if let list = try? decoder.decode([Entry].self, from: data) {
            entries = list
        } else {
            do { entries = try decoder.decode(Wrapped.self, from: data).settings } catch {
                throw MacCtlError.invalidTestMode("MACCTL_TEST_CATALOG is not a catalog: \(error)")
            }
        }
        guard !entries.isEmpty else { throw MacCtlError.invalidTestMode("MACCTL_TEST_CATALOG is empty") }
        var ids: Set<String> = []
        return try entries.map { entry in
            guard ids.insert(entry.id).inserted else { throw MacCtlError.invalidTestMode("duplicate id \(entry.id)") }
            guard entry.backend.appleScript == nil, entry.backend.wallpaper == nil, let defaults = entry.backend.defaults else {
                throw MacCtlError.invalidTestMode("\(entry.id): test mode allows only defaults backends")
            }
            guard defaults.domain.hasPrefix(domainPrefix), defaults.domain.count > domainPrefix.count,
                  !defaults.domain.contains("/") else {
                throw MacCtlError.invalidTestMode("\(entry.id): domain \(defaults.domain) does not start with \(domainPrefix)")
            }
            guard let storage = DefaultsType(rawValue: defaults.type == "double" ? "float" : defaults.type) else {
                throw MacCtlError.invalidTestMode("\(entry.id): unknown defaults type \(defaults.type)")
            }
            let valueType: ValueType
            switch entry.type {
            case "bool": valueType = .bool
            case "int": valueType = .int(min: nil, max: nil)
            case "float", "double": valueType = .double(min: nil, max: nil)
            case "string": valueType = .string
            default: throw MacCtlError.invalidTestMode("\(entry.id): unknown type \(entry.type)")
            }
            let effects: [SideEffect] = try (entry.after ?? []).map { text in
                if text == "logout" { return .logout }
                guard text.hasPrefix("restart:"), text.count > 8 else {
                    throw MacCtlError.invalidTestMode("\(entry.id): after must be restart:<Name> or logout")
                }
                return .restart(process: String(text.dropFirst(8)))
            }
            return Setting(id: entry.id, summary: "test setting \(entry.id)", type: valueType, risk: entry.risk ?? .user,
                           backend: .defaults(domain: defaults.domain, key: defaults.key, type: storage),
                           after: effects, systemDefault: entry.systemDefault,
                           scope: defaults.host ?? .anyHost, sensitive: entry.sensitive ?? false)
        }
    }
}

/// Test mode never restarts real processes; the batch is recorded on stderr for the harness.
public struct TestModeRestarter: Restarter {
    public init() {}
    public func run(_ effects: Set<SideEffect>) async throws {
        let names = effects.compactMap { effect -> String? in
            if case .restart(let process) = effect { return process }
            return nil
        }.sorted()
        FileHandle.standardError.write(Data("macctl test mode: skipped restart \(names.joined(separator: ","))\n".utf8))
    }
}
