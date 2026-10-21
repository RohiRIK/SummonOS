import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// The kill -9 crash matrix (QA plan v3, ADR D2) drives the built `macctl` binary as a subprocess.
//
// - `MACCTL_CRASH_BACKEND=fake|cfprefs` runs the full matrix on that backend. Unset: a smoke subset
//   (O1 on the fake store) so the ordinary `swift test` stays fast.
// - `MACCTL_CRASH_SHARD=k/n` runs every n-th first crash point, starting at k (1-based).
// - `MACCTL_BIN` overrides the binary (default `<package>/.build/debug/macctl`).
// - `MACCTL_CRASH_REPORT=<file>` appends one count line per op, for the CI summary.
//
// Every case gets its own temp root (snapshots, journal, fake store, catalog, HOME) and fresh
// `com.summonos.test.<runid>.<uuid>` domains. Nothing outside that prefix is ever written.
// - `MACCTL_CRASH_RUN_ID=<id>` names this run's domains (CI: run id, attempt, backend, shard), so a
//   run's sweeps touch only its own `com.summonos.test.<runid>.` prefix. Default: `local-<pid>-<random>`.

enum Backend: String { case fake, cfprefs }

enum Config {
    static let environment = ProcessInfo.processInfo.environment
    static var full: Bool { environment["MACCTL_CRASH_BACKEND"].map { !$0.isEmpty } ?? false }
    static var backend: Backend { environment["MACCTL_CRASH_BACKEND"].flatMap(Backend.init(rawValue:)) ?? .fake }
    static var shard: (index: Int, count: Int) {
        let parts = (environment["MACCTL_CRASH_SHARD"] ?? "1/1").split(separator: "/").compactMap { Int($0) }
        guard parts.count == 2, parts[1] >= 1, (1...parts[1]).contains(parts[0]) else { return (1, 1) }
        return (parts[0], parts[1])
    }
    static func owns(_ index: Int) -> Bool { index % shard.count == shard.index - 1 }
    /// This run's domain component: letters, digits and `-` only (a `.` would split the domain).
    static let runID: String = {
        let given = (environment["MACCTL_CRASH_RUN_ID"] ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        if !given.isEmpty { return String(given.prefix(64)) }
        return "local-\(getpid())-\(UUID().uuidString.prefix(8).lowercased())"
    }()
    /// `com.summonos.test.<runid>.`: every domain this run creates starts with it.
    static var runPrefix: String { "com.summonos.test.\(runID)." }
    static var binary: String {
        if let path = environment["MACCTL_BIN"], !path.isEmpty { return path }
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return package.appendingPathComponent(".build/debug/macctl").path
    }
    /// Fixed clock (`MACCTL_TEST_NOW`) so repeated fresh cases get the same session ids.
    static let now = 1_790_000_000

    static func report(_ line: String) {
        print(line)
        guard let path = environment["MACCTL_CRASH_REPORT"], !path.isEmpty else { return }
        let handle = FileHandle(forWritingAtPath: path) ?? {
            FileManager.default.createFile(atPath: path, contents: nil)
            return FileHandle(forWritingAtPath: path)!
        }()
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        handle.closeFile()
    }
}

struct RunResult {
    let status: Int32
    let killed: Bool
    let out: String
    let err: String

    var json: [String: Any]? {
        guard let start = out.firstIndex(of: "{") else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(out[start...].utf8))) as? [String: Any]
    }
    var errorCode: String? { (json?["error"] as? [String: Any])?["code"] as? String }
    var ok: Bool { status == 0 && !killed }
    /// `failpoint <name>@<n>` lines from `MACCTL_FAILPOINT=trace`, as `<name>@<n>`.
    var tracedPoints: [String] {
        err.split(separator: "\n").compactMap { line in
            line.hasPrefix("failpoint ") ? String(line.dropFirst("failpoint ".count)) : nil
        }
    }
    var summary: String { "exit \(status)\(killed ? " (SIGKILL)" : "") stdout=\(out.prefix(400)) stderr=\(err.suffix(400))" }
}

func spawn(_ path: String, _ arguments: [String], environment: [String: String], in directory: URL) -> RunResult {
    let outURL = directory.appendingPathComponent(".out-\(UUID().uuidString)")
    let errURL = directory.appendingPathComponent(".err-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    defer {
        try? FileManager.default.removeItem(at: outURL)
        try? FileManager.default.removeItem(at: errURL)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = directory
    process.standardInput = FileHandle.nullDevice
    let outHandle = FileHandle(forWritingAtPath: outURL.path)!
    let errHandle = FileHandle(forWritingAtPath: errURL.path)!
    process.standardOutput = outHandle
    process.standardError = errHandle
    do { try process.run() } catch {
        return RunResult(status: -1, killed: false, out: "", err: "spawn failed: \(error)")
    }
    process.waitUntilExit()
    outHandle.closeFile()
    errHandle.closeFile()
    let killed = process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL
    return RunResult(status: process.terminationStatus, killed: killed,
                     out: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
                     err: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "")
}

/// The failpoint template a concrete point belongs to (`I2.3@1` → `Ii.3`, `RV1@2` → `RVj`).
func template(of point: String) -> String {
    let name = point.split(separator: "@").first.map(String.init) ?? point
    if name.hasPrefix("RI") || name.hasPrefix("RV"), Int(name.dropFirst(2)) != nil { return "\(name.prefix(2))j" }
    if let first = name.first, "IWAF".contains(first), name.contains(".") {
        return "\(first)i.\(name.split(separator: ".").last!)"
    }
    return name
}

/// A catalog entry in the test catalog.
struct Spec: Sendable {
    enum Domain: Sendable { case a, b }
    var id: String
    var type: String
    var domain: Domain = .a
    var key: String
    var storage: String
    var host: String? = nil
    var after: [String]? = nil
    var sensitive = false
}

/// A seeded value, written with its exact plist type.
enum Seed {
    case bool(Bool), int(Int), real(Double), string(String)

    var defaultsArguments: [String] {
        switch self {
        case .bool(let v): ["-bool", v ? "true" : "false"]
        case .int(let v): ["-int", String(v)]
        case .real(let v): ["-float", String(v)]
        case .string(let v): ["-string", v]
        }
    }
    var object: Any {
        switch self {
        case .bool(let v): v
        case .int(let v): v
        case .real(let v): v
        case .string(let v): v
        }
    }
}

/// One case: a temp root, two fresh test domains, a catalog and the environment macctl runs with.
final class World {
    let backend: Backend
    let root: URL
    let a: String
    let b: String
    let specs: [Spec]
    var now = Config.now
    /// Where `snapshots/` and `journal/` live (O7 builds a second one and merges it).
    var stateDirectory: URL

    var home: URL { root.appendingPathComponent("home") }
    var fake: URL { root.appendingPathComponent("prefs") }
    var catalog: URL { root.appendingPathComponent("catalog.json") }
    var snapshots: URL { stateDirectory.appendingPathComponent("snapshots") }
    var journal: URL { stateDirectory.appendingPathComponent("journal") }

    init(backend: Backend, specs: [Spec]) throws {
        self.backend = backend
        self.specs = specs
        root = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-crash-\(UUID().uuidString)")
        stateDirectory = root.appendingPathComponent("m")
        let uuid = UUID().uuidString.lowercased()
        a = "\(Config.runPrefix)\(uuid)"
        b = "\(Config.runPrefix)\(uuid).b"
        for directory in [root, home, stateDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if backend == .fake { try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true) }
        if backend == .cfprefs { DomainLedger.record([a, b]) }
        try writeCatalog()
    }

    deinit { cleanup() }

    func domain(_ d: Spec.Domain) -> String { d == .a ? a : b }

    func writeCatalog() throws {
        let entries: [[String: Any]] = specs.map { spec in
            var defaults: [String: Any] = ["domain": domain(spec.domain), "key": spec.key, "type": spec.storage]
            if let host = spec.host { defaults["host"] = host }
            var entry: [String: Any] = ["id": spec.id, "type": spec.type, "backend": ["defaults": defaults]]
            if let after = spec.after { entry["after"] = after }
            if spec.sensitive { entry["sensitive"] = true }
            return entry
        }
        let data = try JSONSerialization.data(withJSONObject: ["settings": entries], options: [.sortedKeys])
        try data.write(to: catalog)
    }

    var environment: [String: String] {
        var env: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home.path,
            "TMPDIR": root.path + "/",
            "LANG": "en_US.UTF-8",
            "MACCTL_TEST_MODE": "1",
            "MACCTL_SNAPSHOT_DIR": snapshots.path,
            "MACCTL_TEST_CATALOG": catalog.path,
            "MACCTL_TEST_NOW": String(now),
        ]
        if backend == .fake { env["MACCTL_FAKE_DEFAULTS"] = fake.path }
        return env
    }

    @discardableResult
    func macctl(_ arguments: [String], failpoint: String? = nil, extra: [String: String] = [:]) -> RunResult {
        var env = environment
        if let failpoint { env["MACCTL_FAILPOINT"] = failpoint }
        env.merge(extra) { _, new in new }
        return spawn(Config.binary, arguments + ["--json"], environment: env, in: root)
    }

    func writeProfile(_ settings: [String: Any]) throws -> String {
        let url = root.appendingPathComponent("profile-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: ["version": 1, "name": "crash", "settings": settings], options: [.sortedKeys]).write(to: url)
        return url.path
    }

    // MARK: Preferences

    private func fakeFile(_ appID: String, currentHost: Bool) -> URL {
        fake.appendingPathComponent(currentHost ? "\(appID).currentHost.plist" : "\(appID).plist")
    }

    private func defaults(_ arguments: [String]) -> RunResult {
        var env = environment
        for key in env.keys where key.hasPrefix("MACCTL_") { env.removeValue(forKey: key) }
        return spawn("/usr/bin/defaults", arguments, environment: env, in: root)
    }

    /// Writes (or deletes, with nil) one key the way a user or another app would.
    func seed(_ appID: String, _ key: String, _ value: Seed?, currentHost: Bool = false) throws {
        switch backend {
        case .fake:
            let url = fakeFile(appID, currentHost: currentHost)
            var dict = (try? Data(contentsOf: url)).flatMap {
                try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
            } ?? [:]
            dict[key] = value?.object
            if dict.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else {
                try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
            }
        case .cfprefs:
            let host = currentHost ? ["-currentHost"] : []
            let result = value.map { defaults(host + ["write", appID, key] + $0.defaultsArguments) }
                ?? defaults(host + ["delete", appID, key])
            if value != nil && !result.ok { throw HarnessError("defaults write failed: \(result.summary)") }
        }
    }

    /// One stored value as plist XML text (nil when absent), for the flagged-key checks.
    func value(_ appID: String, _ key: String) -> String? {
        switch backend {
        case .fake:
            guard let data = try? Data(contentsOf: fakeFile(appID, currentHost: false)),
                  let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let value = dict[key] else { return nil }
            return "\(value)"
        case .cfprefs:
            let run = defaults(["read", appID, key])
            return run.ok ? run.out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
    }

    /// Fake-store knobs (plan §2.2): `.fail-writes`, `.drop-writes` (lists) and `.read-back` (dict).
    func knob(_ name: String, _ object: Any) throws {
        precondition(backend == .fake)
        try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            .write(to: fake.appendingPathComponent(name))
    }

    /// The oracle: every test-domain scope, as canonical XML (or ABSENT). Fake: every domain file,
    /// byte for byte (the global layer included). cfprefs: `defaults [-currentHost] export`.
    func state() -> [String: String] {
        var result: [String: String] = [:]
        switch backend {
        case .fake:
            let names = (try? FileManager.default.contentsOfDirectory(atPath: fake.path)) ?? []
            for name in names where !name.hasPrefix(".") {
                let data = (try? Data(contentsOf: fake.appendingPathComponent(name))) ?? Data()
                result[name.replacingOccurrences(of: b, with: "<B>").replacingOccurrences(of: a, with: "<A>")] =
                    String(decoding: data, as: UTF8.self)
            }
        case .cfprefs:
            for (label, appID) in [("A", a), ("B", b)] {
                for currentHost in [false, true] {
                    let run = spawn("/bin/sh", ["-c", "defaults \(currentHost ? "-currentHost " : "")export \"$0\" - | plutil -convert xml1 -o - -", appID],
                                    environment: ["PATH": "/usr/bin:/bin", "HOME": home.path], in: root)
                    result["\(label)\(currentHost ? ".currentHost" : "")"] = canonical(run.ok ? Data(run.out.utf8) : nil)
                }
            }
        }
        return result
    }

    private func canonical(_ data: Data?) -> String {
        guard let data, !data.isEmpty,
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              !dict.isEmpty else { return "ABSENT" }
        return String(decoding: (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? data,
                      as: UTF8.self)
    }

    private var cleaned = false

    /// Idempotent. Callers run it from `defer`; deinit is only the backstop.
    func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        if backend == .cfprefs {
            for appID in [a, b] { removeCFPreferencesDomain(appID) }
            DomainLedger.forget([a, b])
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Snapshots and journal

    func headerIDs() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: snapshots.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { String($0.dropLast(5)) }.sorted()
    }

    func journalNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: journal.path)) ?? []).filter { $0.hasSuffix(".jsonl") }.sorted()
    }

    func journalBytes() -> [String: Data] {
        Dictionary(uniqueKeysWithValues: journalNames().map {
            ($0, (try? Data(contentsOf: journal.appendingPathComponent($0))) ?? Data())
        })
    }

    /// Parsed journal lines per file; a line that does not parse is nil.
    func journalLines() -> [String: [[String: Any]?]] {
        journalBytes().mapValues { data in
            String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
        }
    }

    /// Journal content ignoring `ts` and `seq`, with the per-case domains replaced (rerun equality).
    func normalizedJournal() -> [String] {
        journalLines().sorted { $0.key < $1.key }.flatMap { name, lines in
            lines.map { line -> String in
                guard var line else { return "\(name): <torn>" }
                line.removeValue(forKey: "ts")
                line.removeValue(forKey: "seq")
                let data = (try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])) ?? Data()
                return "\(name): " + String(decoding: data, as: UTF8.self)
                    .replacingOccurrences(of: b, with: "<B>").replacingOccurrences(of: a, with: "<A>")
            }
        }
    }

    struct HeaderPrint: Equatable {
        let inode: UInt64
        let mtime: Double
        let bytes: Data
    }

    func headerPrints() -> [String: HeaderPrint] {
        var result: [String: HeaderPrint] = [:]
        for id in headerIDs() {
            let url = snapshots.appendingPathComponent("\(id).json")
            var info = stat()
            guard stat(url.path, &info) == 0, let bytes = try? Data(contentsOf: url) else { continue }
            #if canImport(Darwin)
            let mtime = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
            #else
            let mtime = Double(info.st_mtim.tv_sec) + Double(info.st_mtim.tv_nsec) / 1e9
            #endif
            result[id] = HeaderPrint(inode: UInt64(info.st_ino), mtime: mtime, bytes: bytes)
        }
        return result
    }

    /// `snapshot list --json`: id → derived status.
    func statuses() -> [String: String] {
        let run = macctl(["snapshot", "list"])
        var result: [String: String] = [:]
        if let list = run.json?["result"] as? [[String: Any]] {
            for item in list { if let id = item["id"] as? String { result[id] = item["status"] as? String ?? "?" } }
        }
        return result
    }

    func mode(_ url: URL) -> Int? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Int(info.st_mode) & 0o777
    }

    /// The transaction lock can be taken without waiting (no process still holds it).
    func lockIsFree() -> Bool {
        let url = snapshots.appendingPathComponent(".transaction.lock")
        let fd = open(url.path, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        flock(fd, LOCK_UN)
        return true
    }
}

/// Every test domain this process created, for the final sweep at exit (cfprefs). Each World also
/// cleans up explicitly (callers `defer { w.cleanup() }`); this catches anything a crash in the
/// harness itself or a retained World would leave.
enum DomainLedger {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var domains: Set<String> = []
    nonisolated(unsafe) private static var registered = false

    static func record(_ names: [String]) {
        lock.withLock {
            domains.formUnion(names)
            if !registered {
                registered = true
                sweepStale()
                atexit { DomainLedger.sweep(); DomainLedger.sweepRun() }
            }
        }
    }

    static func forget(_ names: [String]) { lock.withLock { domains.subtract(names) } }

    /// Start of a cfprefs run: remove `com.summonos.test.*` domains an earlier run left behind
    /// (cfprefsd keys and plist files, both host scopes). Scoped so another run on the same Mac is
    /// never touched: this run's own prefix is skipped, and only domains whose plist files are all
    /// older than 10 minutes are swept (a live run rewrites its domains within seconds).
    static func sweepStale(olderThan age: TimeInterval = 10 * 60) {
        sweep(matching: { !$0.hasPrefix(Config.runPrefix) }, olderThan: age, label: "start sweep removed", unit: "stale test domains (older than \(Int(age / 60)) min)")
    }

    /// End of a run: every domain under this run's own `com.summonos.test.<runid>.` prefix, even one
    /// the ledger missed. Never another run's.
    static func sweepRun() {
        sweep(matching: { $0.hasPrefix(Config.runPrefix) }, olderThan: nil, label: "run sweep removed", unit: "test domains of run \(Config.runID)")
    }

    private static func sweep(matching include: (String) -> Bool, olderThan age: TimeInterval?, label: String, unit: String) {
        let preferences = URL(fileURLWithPath: realHome()).appendingPathComponent("Library/Preferences")
        let byHost = preferences.appendingPathComponent("ByHost")
        let prefix = "com.summonos.test."
        let cutoff = Date().addingTimeInterval(-(age ?? 0))
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
        }
        // appID → newest plist mtime across both host scopes.
        var newest: [String: Date] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? []
        where name.hasPrefix(prefix) && name.hasSuffix(".plist") {
            let appID = String(name.dropLast(6))
            newest[appID] = max(newest[appID] ?? .distantPast, modified(preferences.appendingPathComponent(name)))
        }
        var byHostFiles: [(appID: String, url: URL)] = []
        for name in (try? FileManager.default.contentsOfDirectory(atPath: byHost.path)) ?? []
        where name.hasPrefix(prefix) && name.hasSuffix(".plist") {
            // <appID>.<host UUID>.plist
            let parts = name.dropLast(6).split(separator: ".")
            guard parts.count > 1 else { continue }
            let appID = parts.dropLast().joined(separator: ".")
            let url = byHost.appendingPathComponent(name)
            byHostFiles.append((appID, url))
            newest[appID] = max(newest[appID] ?? .distantPast, modified(url))
        }
        let stale = newest.filter { include($0.key) && (age == nil || $0.value < cutoff) }.map(\.key).sorted()
        for appID in stale { removeCFPreferencesDomain(appID) }
        for file in byHostFiles where stale.contains(file.appID) { try? FileManager.default.removeItem(at: file.url) }
        if !stale.isEmpty { print("crash-matrix: \(label) \(stale.count) \(unit)") }
    }

    static func sweep() {
        let left = lock.withLock { domains }
        for appID in left.sorted() { removeCFPreferencesDomain(appID) }
        if !left.isEmpty { print("crash-matrix: final sweep removed \(left.count) test domains") }
    }
}

/// The real user's home: CFPreferences ignores `HOME`, so test domains land in the real
/// `~/Library/Preferences` even though each case runs with a temp HOME.
func realHome() -> String {
    if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir { return String(cString: dir) }
    return NSHomeDirectory()
}

/// Deletes a test domain from cfprefsd in both host scopes, then removes its plist files (cfprefsd
/// leaves an empty `<domain>.plist` behind, which `defaults domains` still lists). Only ever called
/// with `com.summonos.test.` names.
func removeCFPreferencesDomain(_ appID: String) {
    precondition(appID.hasPrefix("com.summonos.test.") && !appID.contains("/"))
    let env = ["PATH": "/usr/bin:/bin", "HOME": realHome()]
    let tmp = FileManager.default.temporaryDirectory
    _ = spawn("/usr/bin/defaults", ["delete", appID], environment: env, in: tmp)
    _ = spawn("/usr/bin/defaults", ["-currentHost", "delete", appID], environment: env, in: tmp)
    let preferences = URL(fileURLWithPath: realHome()).appendingPathComponent("Library/Preferences")
    try? FileManager.default.removeItem(at: preferences.appendingPathComponent("\(appID).plist"))
    let byHost = preferences.appendingPathComponent("ByHost")
    for name in (try? FileManager.default.contentsOfDirectory(atPath: byHost.path)) ?? []
    where name.hasPrefix("\(appID).") && name.hasSuffix(".plist") && !name.dropFirst(appID.count + 1).dropLast(6).contains(".") {
        try? FileManager.default.removeItem(at: byHost.appendingPathComponent(name))
    }
}

struct HarnessError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
