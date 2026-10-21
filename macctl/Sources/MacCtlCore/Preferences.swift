import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The property-list type a value is stored as (ADR D1, from `CFGetTypeID`).
public enum PlistType: String, Sendable, Hashable, Codable, CaseIterable {
    case bool, int, float, string, data, date, array, dict
}

/// Which host scope a preference lives in: `kCFPreferencesAnyHost` (the default, what `defaults write`
/// uses) or `kCFPreferencesCurrentHost` (`defaults -currentHost`, ByHost plists).
public enum PreferenceHost: String, Sendable, Hashable, Codable {
    case anyHost, currentHost

    public var opposite: PreferenceHost { self == .anyHost ? .currentHost : .anyHost }
}

/// A stored preference with its exact type, so restore rebuilds the same CF object
/// (`kCFBooleanTrue`, never `NSNumber(1)`; an int stays SInt64; `<real>64</real>` stays real).
///
/// JSON: scalars as `{"type":"int","value":64}`; data, date, array and dict as
/// `{"type":"array","plist":"<base64 binary plist>"}` so nested types round-trip losslessly.
public struct TypedValue: Sendable, Hashable, Codable, CustomStringConvertible {
    public let type: PlistType
    public let value: Value

    public init(type: PlistType, value: Value) {
        self.type = type
        self.value = value
    }

    /// Infers the plist type from the value's case (used for non-`defaults` backends and fakes).
    public init(_ value: Value) {
        switch value {
        case .bool: type = .bool
        case .int: type = .int
        case .double: type = .float
        case .string: type = .string
        case .data: type = .data
        case .date: type = .date
        case .array: type = .array
        case .dictionary: type = .dict
        }
        self.value = value
    }

    /// The value a catalog `DefaultsType` writes (`-float` with an integer stays a real).
    public init(writing value: Value, as type: DefaultsType) {
        switch (type, value) {
        case (.float, .int(let i)): self.init(type: .float, value: .double(Double(i)))
        default: self.init(type: type.plistType, value: value)
        }
    }

    private enum CodingKeys: String, CodingKey { case type, value, plist }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(PlistType.self, forKey: .type)
        switch type {
        case .bool, .int, .float, .string:
            let raw = try c.decode(Value.self, forKey: .value)
            switch (type, raw) {
            case (.bool, .bool), (.int, .int), (.string, .string), (.float, .double): value = raw
            case (.float, .int(let i)): value = .double(Double(i)) // JSON prints 64.0 as 64
            default:
                throw DecodingError.dataCorruptedError(forKey: .value, in: c, debugDescription: "value does not match type \(type)")
            }
        case .data, .date, .array, .dict:
            let text = try c.decode(String.self, forKey: .plist)
            guard let data = Data(base64Encoded: text) else {
                throw DecodingError.dataCorruptedError(forKey: .plist, in: c, debugDescription: "invalid base64")
            }
            let object = try PropertyListSerialization.propertyList(from: data, format: nil)
            let decoded = try PlistBridge.typed(from: object)
            guard decoded.type == type else {
                throw DecodingError.dataCorruptedError(forKey: .plist, in: c, debugDescription: "plist does not match type \(type)")
            }
            value = decoded.value
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        switch type {
        case .bool, .int, .float, .string:
            try c.encode(value, forKey: .value)
        case .data, .date, .array, .dict:
            let data = try PropertyListSerialization.data(
                fromPropertyList: PlistBridge.object(from: value), format: .binary, options: 0)
            try c.encode(data.base64EncodedString(), forKey: .plist)
        }
    }

    public var description: String { "\(value) (\(type.rawValue))" }

    /// Canonical bytes for hashing sensitive values: the binary plist of a one-element array, so
    /// type and value both count and the encoding is the same on every run.
    func canonicalData() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [PlistBridge.object(from: value)], format: .binary, options: 0)
    }

    /// The value as the catalog type sees it, for planning and display. Nil when the stored type
    /// cannot be read as that type (the exact prior is still journaled and restored).
    public func catalogValue(_ type: DefaultsType) -> Value? {
        switch (type, value) {
        case (.bool, .bool): return value
        case (.bool, .int(let i)) where i == 0 || i == 1: return .bool(i == 1)
        case (.bool, .string(let s)): return SystemBackend.parseBool(s).map(Value.bool)
        case (.int, .int): return value
        case (.int, .double(let d)) where d.rounded() == d && abs(d) < 1e15: return .int(Int(d))
        case (.int, .bool(let b)): return .int(b ? 1 : 0)
        case (.float, .double): return value
        case (.float, .int(let i)): return .double(Double(i))
        case (.string, .string): return value
        case (.string, .int(let i)): return .string(String(i))
        case (.string, .double(let d)): return .string(String(d))
        case (.string, .bool(let b)): return .string(b ? "1" : "0")
        default: return nil
        }
    }
}

extension DefaultsType {
    public var plistType: PlistType {
        switch self {
        case .bool: .bool
        case .int: .int
        case .float: .float
        case .string: .string
        }
    }
}

/// Converts between `Value` and property-list objects without losing bool/int/real distinctions.
enum PlistBridge {
    static func object(from value: Value) -> Any {
        switch value {
        case .bool(let b): return b
        case .int(let i): return NSNumber(value: Int64(i))
        case .double(let d): return NSNumber(value: d)
        case .string(let s): return s
        case .data(let d): return d
        case .date(let d): return d
        case .array(let a): return a.map(object(from:))
        case .dictionary(let d): return d.mapValues(object(from:))
        }
    }

    static func typed(from object: Any) throws -> TypedValue {
        #if canImport(Darwin)
        let cf = object as CFTypeRef
        if CFGetTypeID(cf) == CFBooleanGetTypeID() { return TypedValue(type: .bool, value: .bool(CFBooleanGetValue((cf as! CFBoolean)))) }
        if CFGetTypeID(cf) == CFNumberGetTypeID() {
            let number = cf as! CFNumber
            if CFNumberIsFloatType(number) { return TypedValue(type: .float, value: .double((number as NSNumber).doubleValue)) }
            return TypedValue(type: .int, value: .int((number as NSNumber).intValue))
        }
        #else
        if type(of: object) == Bool.self, let b = object as? Bool { return TypedValue(type: .bool, value: .bool(b)) }
        if let number = object as? NSNumber {
            let code = String(cString: number.objCType)
            if code == "c" || code == "B" { return TypedValue(type: .bool, value: .bool(number.boolValue)) }
            if code == "d" || code == "f" { return TypedValue(type: .float, value: .double(number.doubleValue)) }
            return TypedValue(type: .int, value: .int(number.intValue))
        }
        #endif
        if let s = object as? String { return TypedValue(type: .string, value: .string(s)) }
        if let d = object as? Data { return TypedValue(type: .data, value: .data(d)) }
        if let d = object as? Date { return TypedValue(type: .date, value: .date(d)) }
        if let a = object as? [Any] { return TypedValue(type: .array, value: .array(try a.map { try typed(from: $0).value })) }
        if let d = object as? [String: Any] {
            return TypedValue(type: .dict, value: .dictionary(try d.mapValues { try typed(from: $0).value }))
        }
        throw MacCtlError.unsupported(id: "preferences", reason: "unsupported property-list type \(type(of: object))")
    }
}

/// The preferences system, as one `(appID, user = current, host)` triple per call (ADR D1). The real
/// implementation is CFPreferences on macOS; tests and Linux CI use a fake with the same layering.
public protocol PreferencesStore: Sendable {
    /// `CFPreferencesAppValueIsForced`: a managed (MDM / configuration profile) value.
    func isForced(_ key: String, appID: String) throws -> Bool
    /// `CFPreferencesCopyValue` for the exact triple; nil when this triple has no explicit value.
    func copyValue(_ key: String, appID: String, host: PreferenceHost) throws -> TypedValue?
    /// `CFPreferencesCopyAppValue`: the effective, layered value (other host, global domain, managed).
    func copyAppValue(_ key: String, appID: String) throws -> TypedValue?
    /// `CFPreferencesSetValue`; nil deletes only this triple's explicit key.
    func setValue(_ value: TypedValue?, key: String, appID: String, host: PreferenceHost) throws
    /// `CFPreferencesAppSynchronize` (anyHost) / `CFPreferencesSynchronize` (currentHost).
    func synchronize(appID: String, host: PreferenceHost) throws
}

extension PreferencesStore {
    /// Where an inherited value comes from, when it can be told: `global`, `otherHost` or `unknown`.
    public func inheritedLayer(_ key: String, appID: String, host: PreferenceHost) throws -> String {
        if try copyValue(key, appID: appID, host: host.opposite) != nil { return "otherHost" }
        if appID != Backend.globalDomain {
            if try copyValue(key, appID: Backend.globalDomain, host: .anyHost) != nil { return "global" }
            if try copyValue(key, appID: Backend.globalDomain, host: .currentHost) != nil { return "global" }
        }
        return "unknown"
    }
}

/// Fakes share CFPreferences' lookup order: this app (current host, any host), then the global
/// domain (current host, any host). Managed values win over everything.
protocol LayeredPreferences: PreferencesStore {
    func forcedValue(_ key: String, appID: String) throws -> TypedValue?
}

extension LayeredPreferences {
    public func copyAppValue(_ key: String, appID: String) throws -> TypedValue? {
        if let forced = try forcedValue(key, appID: appID) { return forced }
        var layers: [(String, PreferenceHost)] = [(appID, .currentHost), (appID, .anyHost)]
        if appID != Backend.globalDomain {
            layers += [(Backend.globalDomain, .currentHost), (Backend.globalDomain, .anyHost)]
        }
        for (app, host) in layers {
            if let value = try copyValue(key, appID: app, host: host) { return value }
        }
        return nil
    }
}

/// In-memory preferences for unit tests: `values[appID][host][key]`, plus managed keys.
public final class MemoryPreferencesStore: LayeredPreferences, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: [PreferenceHost: [String: TypedValue]]] = [:]
    private var managed: [String: TypedValue] = [:]
    private var failing: Set<String> = []
    private var substitutes: [String: TypedValue] = [:]
    public private(set) var writes = 0
    public private(set) var syncs = 0

    public init() {}

    public func seed(_ key: String, _ value: TypedValue?, appID: String, host: PreferenceHost = .anyHost) {
        lock.withLock { values[appID, default: [:]][host, default: [:]][key] = value }
    }

    public func force(_ key: String, _ value: TypedValue, appID: String) {
        lock.withLock { managed["\(appID)/\(key)"] = value }
    }

    public func failWrites(_ key: String?, appID: String) {
        lock.withLock {
            if let key { failing.insert("\(appID)/\(key)") } else { failing = [] }
        }
    }

    /// The next write to this key lands as `value` instead (a third value on read-back).
    public func landWrites(_ key: String, as value: TypedValue, appID: String) {
        lock.withLock { substitutes["\(appID)/\(key)"] = value }
    }

    public func isForced(_ key: String, appID: String) throws -> Bool {
        lock.withLock { managed["\(appID)/\(key)"] != nil }
    }

    func forcedValue(_ key: String, appID: String) throws -> TypedValue? {
        lock.withLock { managed["\(appID)/\(key)"] }
    }

    public func copyValue(_ key: String, appID: String, host: PreferenceHost) throws -> TypedValue? {
        lock.withLock { values[appID]?[host]?[key] }
    }

    public func setValue(_ value: TypedValue?, key: String, appID: String, host: PreferenceHost) throws {
        try lock.withLock {
            if failing.contains("\(appID)/\(key)") {
                throw MacCtlError.commandFailed(command: "CFPreferencesSetValue \(appID) \(key)", exitCode: 1, stderr: "injected failure")
            }
            values[appID, default: [:]][host, default: [:]][key] = substitutes.removeValue(forKey: "\(appID)/\(key)") ?? value
            writes += 1
        }
    }

    public func synchronize(appID: String, host: PreferenceHost) throws {
        lock.withLock { syncs += 1 }
    }
}

/// A type-preserving, cross-process preferences fake for test mode (`MACCTL_FAKE_DEFAULTS=<dir>`) and
/// the Linux crash matrix. One XML plist per domain and host, written with sorted keys so bytes are
/// deterministic:
///
/// - `<dir>/<appID>.plist` (anyHost), `<dir>/<appID>.currentHost.plist` (currentHost);
///   the global domain is `NSGlobalDomain`.
/// - `<dir>/.managed.plist`: `{"<appID>/<key>": value}` forced values.
/// - `<dir>/.fail-writes.plist`: `["<appID>/<key>"]` writes that fail (injected error).
///
/// Each set is read-modify-write through a 0600 temp file, fsync and rename, so a kill -9 leaves
/// either the old or the new file, never a torn one (like cfprefsd's write-through). A domain
/// whose last key is deleted removes its file.
public struct PlistFilePreferencesStore: LayeredPreferences {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func file(appID: String, host: PreferenceHost) -> URL {
        directory.appendingPathComponent(host == .anyHost ? "\(appID).plist" : "\(appID).currentHost.plist")
    }

    public func isForced(_ key: String, appID: String) throws -> Bool {
        try forcedValue(key, appID: appID) != nil
    }

    func forcedValue(_ key: String, appID: String) throws -> TypedValue? {
        let managed = try Self.load(directory.appendingPathComponent(".managed.plist"))
        return try managed["\(appID)/\(key)"].map(PlistBridge.typed(from:))
    }

    public func copyValue(_ key: String, appID: String, host: PreferenceHost) throws -> TypedValue? {
        try Self.load(file(appID: appID, host: host))[key].map(PlistBridge.typed(from:))
    }

    public func setValue(_ value: TypedValue?, key: String, appID: String, host: PreferenceHost) throws {
        try Self.validateName(appID)
        let failing = directory.appendingPathComponent(".fail-writes.plist")
        if let data = try? Data(contentsOf: failing),
           let list = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
           list.contains("\(appID)/\(key)") {
            throw MacCtlError.commandFailed(command: "CFPreferencesSetValue \(appID) \(key)", exitCode: 1, stderr: "injected failure")
        }
        let url = file(appID: appID, host: host)
        var domain = try Self.load(url)
        domain[key] = value.map { PlistBridge.object(from: $0.value) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if domain.isEmpty {
            if unlink(url.path) != 0 && errno != ENOENT { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try Durable.syncDirectory(directory)
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
        try Durable.replace(url, with: data, temporaryPrefix: ".prefs-")
    }

    public func synchronize(appID: String, host: PreferenceHost) throws {}

    /// Canonical bytes of one domain file (empty when absent), for the byte-identity oracle.
    public func bytes(appID: String, host: PreferenceHost = .anyHost) -> Data {
        (try? Data(contentsOf: file(appID: appID, host: host))) ?? Data()
    }

    static func load(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw MacCtlError.invalidProfile("\(url.lastPathComponent) is not a preferences dictionary")
        }
        return dict
    }

    static func validateName(_ appID: String) throws {
        guard !appID.isEmpty, !appID.contains("/"), !appID.hasPrefix(".") else {
            throw MacCtlError.invalidProfile("invalid preferences domain \(appID)")
        }
    }
}

/// Placeholder where CFPreferences does not exist (Linux) and no fake was configured.
public struct UnavailablePreferencesStore: PreferencesStore {
    public init() {}
    private func fail() -> MacCtlError { .unsupported(id: "preferences", reason: "CFPreferences requires macOS") }
    public func isForced(_ key: String, appID: String) throws -> Bool { throw fail() }
    public func copyValue(_ key: String, appID: String, host: PreferenceHost) throws -> TypedValue? { throw fail() }
    public func copyAppValue(_ key: String, appID: String) throws -> TypedValue? { throw fail() }
    public func setValue(_ value: TypedValue?, key: String, appID: String, host: PreferenceHost) throws { throw fail() }
    public func synchronize(appID: String, host: PreferenceHost) throws { throw fail() }
}

/// Small durable-file helpers shared by the snapshot store, the journal and the fake preferences.
enum Durable {
    static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    /// `F_FULLFSYNC` on Darwin (plain fsync does not flush the drive cache there), fsync elsewhere.
    /// When F_FULLFSYNC is not supported (some file systems, e.g. network or FUSE mounts) this falls
    /// back to fsync silently: the strongest flush the file system offers.
    static func fullSync(_ descriptor: Int32) throws {
        #if canImport(Darwin)
        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        #endif
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    static func syncDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    /// Writes a new 0600 file exclusively (O_CREAT|O_EXCL|O_NOFOLLOW) and fsyncs it.
    static func writeExclusive(_ url: URL, _ data: Data) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw posixError() }
        try writeAll(descriptor, data)
        try fullSync(descriptor)
    }

    static func writeAll(_ descriptor: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let n = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                offset += n
            }
        }
    }

    /// Atomically replaces `url`: 0600 temp in the same directory, fsync, rename, directory fsync.
    /// Permissions are final before the name appears (QA R-f). `hit` marks the failpoints.
    static func replace(_ url: URL, with data: Data, temporaryPrefix: String,
                        hit: (String) -> Void = { _ in }, points: [String]? = nil) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent("\(temporaryPrefix)\(UUID().uuidString).tmp")
        do {
            try writeExclusive(temporary, data)
            if let points { hit(points[0]) }
            guard rename(temporary.path, url.path) == 0 else { throw posixError() }
            if let points { hit(points[1]) }
        } catch {
            unlink(temporary.path)
            throw error
        }
        try syncDirectory(directory)
        if let points { hit(points[2]) }
    }

    /// Removes leftover `<prefix>*.tmp` files (a SIGKILL skips cleanup; QA R-g). Call under the lock.
    static func removeTemporaries(in directory: URL, prefixes: [String]) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(".tmp") && prefixes.contains(where: { name.hasPrefix($0) }) {
            unlink(directory.appendingPathComponent(name).path)
        }
    }
}
