import Foundation

/// `macctl discover`: finds the preference key behind a System Settings control, read-only.
///
/// New macOS releases add controls before anyone documents their keys (macOS 27's Liquid Glass
/// slider is one). Guessing a key and writing it is how tools break Macs, so macctl records what is
/// there instead: `discover start` saves every explicit key of a set of domains (both host scopes),
/// the user changes one control in System Settings, and `discover diff` lists exactly the keys that
/// changed, with their exact types and a catalog entry to review. Nothing is ever written to
/// preferences. The baseline file is 0600 because domains can hold paths and other personal values;
/// `diff` prints only the keys that changed.
public enum Discovery {
    /// Where System Settings controls usually land. `--domain` replaces this list.
    public static let defaultDomains = [
        Backend.globalDomain,
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.menuextra.clock",
        "com.apple.screencapture",
        "com.apple.universalaccess",
        "com.apple.Spotlight",
        "com.apple.HIToolbox",
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
        "com.apple.wallpaper",
        "com.apple.notificationcenterui",
    ]

    /// One domain and host scope, as captured.
    public struct Domain: Sendable, Hashable, Codable {
        public let appID: String
        public let host: PreferenceHost
        public let values: [String: TypedValue]
    }

    public struct Baseline: Sendable, Hashable, Codable {
        public let createdAt: Date
        public let macOSVersion: String
        public let domains: [Domain]
    }

    /// One key that differs between the baseline and now.
    public struct Change: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Hashable, Codable { case added, removed, changed }
        public let appID: String
        public let host: PreferenceHost
        public let key: String
        public let kind: Kind
        public let before: TypedValue?
        public let after: TypedValue?
        /// A draft `Catalog` entry for a scalar key (nil for data, dates and containers).
        public let suggestion: String?
    }

    public struct Report: Sendable, Hashable, Codable {
        public let baselineCreatedAt: Date
        public let macOSVersion: String
        public let domains: [String]
        public let changes: [Change]
    }

    /// Reads both host scopes of every domain. A domain that cannot be read (for example a
    /// privacy-protected one) is recorded empty rather than failing the whole capture.
    public static func capture(_ store: any PreferencesStore, domains: [String], macOSVersion: String,
                               now: Date = Date()) -> Baseline {
        var captured: [Domain] = []
        for appID in domains {
            for host in [PreferenceHost.anyHost, .currentHost] {
                let values = (try? store.allValues(appID: appID, host: host)) ?? [:]
                captured.append(Domain(appID: appID, host: host, values: values))
            }
        }
        return Baseline(createdAt: now, macOSVersion: macOSVersion, domains: captured)
    }

    /// Keys added, removed or changed (value or type) since `baseline`, sorted by domain, host, key.
    public static func diff(_ baseline: Baseline, _ current: Baseline) -> Report {
        var changes: [Change] = []
        let now = Dictionary(current.domains.map { ("\($0.appID)|\($0.host.rawValue)", $0) }, uniquingKeysWith: { a, _ in a })
        for old in baseline.domains {
            let new = now["\(old.appID)|\(old.host.rawValue)"]?.values ?? [:]
            for key in Set(old.values.keys).union(new.keys).sorted() {
                let before = old.values[key]
                let after = new[key]
                guard before != after else { continue }
                let kind: Change.Kind = before == nil ? .added : (after == nil ? .removed : .changed)
                changes.append(Change(appID: old.appID, host: old.host, key: key, kind: kind, before: before, after: after,
                                      suggestion: suggestion(appID: old.appID, host: old.host, key: key, value: after ?? before)))
            }
        }
        changes.sort { ($0.appID, $0.host.rawValue, $0.key) < ($1.appID, $1.host.rawValue, $1.key) }
        return Report(baselineCreatedAt: baseline.createdAt, macOSVersion: current.macOSVersion,
                      domains: baseline.domains.map(\.appID).reduce(into: []) { if !$0.contains($1) { $0.append($1) } },
                      changes: changes)
    }

    /// A catalog entry to review by hand: id, summary, range and default still need a human.
    static func suggestion(appID: String, host: PreferenceHost, key: String, value: TypedValue?) -> String? {
        guard let value else { return nil }
        let types: (value: String, stored: String)? = switch value.type {
        case .bool: (".bool", ".bool")
        case .int: (".int(min: nil, max: nil)", ".int")
        case .float: (".double(min: nil, max: nil)", ".float")
        case .string: (".string", ".string")
        case .data, .date, .array, .dict: nil
        }
        guard let types else { return nil }
        let domain = appID == Backend.globalDomain ? "Backend.globalDomain" : "\"\(appID)\""
        let scope = host == .currentHost ? ", scope: .currentHost" : ""
        let id = key.lowercased().filter { $0.isLetter || $0.isNumber }
        return "Setting(id: \"<domain>.\(id)\", summary: \"<what it does>\", type: \(types.value), "
            + "backend: .defaults(domain: \(domain), key: \"\(key)\", type: \(types.stored))\(scope), verifiedOn: [])"
    }
}

/// The saved baseline: `~/Library/Application Support/macctl/discover/baseline.json`, mode 0600.
public struct DiscoveryStore: Sendable {
    public let file: URL

    public init(file: URL = FileSnapshotStore.defaultDirectory.deletingLastPathComponent()
        .appendingPathComponent("discover/baseline.json")) {
        self.file = file
    }

    public func save(_ baseline: Discovery.Baseline) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(baseline)
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Durable.replace(file, with: data, temporaryPrefix: ".baseline-")
    }

    public func load() throws -> Discovery.Baseline {
        guard let data = try? Data(contentsOf: file) else {
            throw MacCtlError.invalidProfile("no discover baseline at \(file.path); run `macctl discover start` first")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(Discovery.Baseline.self, from: data) } catch {
            throw MacCtlError.invalidProfile("discover baseline \(file.path) is unreadable: \(error)")
        }
    }
}
