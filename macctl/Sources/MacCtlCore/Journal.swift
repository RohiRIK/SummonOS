import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A value as the journal records it: absent, an exact typed value, or (sensitive settings) the
/// type plus `hmac = HMAC-SHA256(perInstallKey, canonical value)`.
public struct RecordedValue: Sendable, Hashable, Codable {
    public let absent: Bool?
    public let value: TypedValue?
    public let type: PlistType?
    public let hmac: String?

    public static let missing = RecordedValue(absent: true, value: nil, type: nil, hmac: nil)

    public init(absent: Bool?, value: TypedValue?, type: PlistType?, hmac: String?) {
        self.absent = absent
        self.value = value
        self.type = type
        self.hmac = hmac
    }

    /// Records `value` in the clear, or as a keyed hash when `sensitive`.
    static func record(_ value: TypedValue?, sensitive: Bool, key: () throws -> Data) throws -> RecordedValue {
        guard let value else { return .missing }
        guard sensitive else { return RecordedValue(absent: nil, value: value, type: value.type, hmac: nil) }
        return RecordedValue(absent: nil, value: nil, type: value.type,
                             hmac: HMACSHA256.hex(try value.canonicalData(), key: try key()))
    }

    /// Whether the current exact-triple value is this recorded value (type and value, or HMAC).
    func matches(_ current: TypedValue?, key: () throws -> Data) throws -> Bool {
        if absent == true { return current == nil }
        guard let current else { return false }
        if let value { return value == current }
        guard let hmac, current.type == type else { return false }
        return HMACSHA256.hex(try current.canonicalData(), key: try key()) == hmac
    }
}

extension PriorState {
    /// The exact-triple value restore must leave: nothing (absent, inherited) or the explicit value.
    var restoredValue: RecordedValue {
        restoresByDeleting ? .missing : RecordedValue(absent: nil, value: value, type: type, hmac: hmac)
    }

    /// A sensitive explicit prior was stored as a hash only, so it can be compared but not restored.
    var isRestorable: Bool { restoresByDeleting || value != nil }

    /// Drops the plain value of a sensitive setting, keeping type and hash (ADR D2 Privacy, Q2).
    func redacted(sensitive: Bool, key: () throws -> Data) throws -> PriorState {
        guard sensitive, let value else { return self }
        let hash = HMACSHA256.hex(try value.canonicalData(), key: try key())
        return PriorState(state: state, value: nil, host: host, layer: layer, shadowedBy: shadowedBy,
                          type: value.type, hmac: state == .explicit ? hash : nil)
    }
}

/// One JSONL line. Status is never rewritten in place: the lifecycle is new lines (ADR D2):
/// session_start; intent → applied | failed | flagged; applied → revert_intent → reverted |
/// revert_flagged; session_end{completed | rolled_back | undone | recovered}.
public struct JournalRecord: Sendable, Hashable, Codable {
    public enum Op: String, Sendable, Hashable, Codable {
        case sessionStart = "session_start"
        case intent, applied, failed, flagged, reverted
        case revertIntent = "revert_intent"
        case revertFlagged = "revert_flagged"
        case sessionEnd = "session_end"
    }

    public var v: Int = 1
    public var seq: Int
    public var ts: Date
    public var op: Op
    // session_start
    /// The legacy snapshot this session undoes (undo of a pre-journal snapshot).
    public var undoes: String?
    // intent
    /// 1-based position of the change in its session (the `i` of the failpoints).
    public var index: Int?
    public var settingID: String?
    public var domain: String?
    public var key: String?
    public var host: PreferenceHost?
    /// intent and revert_intent: the state a revert restores.
    public var prior: PriorState?
    public var new: RecordedValue?
    /// Wallpaper settings: the per-display pictures before the change (restored per display).
    public var wallpapers: [DisplayWallpaper]?
    public var after: [String]?
    public var sensitive: Bool?
    // applied / failed / flagged / revert_intent / reverted / revert_flagged
    public var ref: Int?
    /// revert_intent: the value macctl wrote and expects to find (the intent's `new`).
    public var expected: RecordedValue?
    public var observed: RecordedValue?
    public var reason: String?
    public var forced: Bool?
    // session_end
    public var outcome: String?

    public init(seq: Int, ts: Date, op: Op) {
        self.seq = seq
        self.ts = ts
        self.op = op
    }
}

/// Where per-session journals live. `FileJournalStore` is the real one; tests use `MemoryJournalStore`.
public protocol JournalStore: Sendable {
    /// Creates `<id>`'s journal exclusively (fails when it exists).
    func create(_ id: String) throws -> any JournalSink
    /// Opens an existing journal for appending after dropping a torn last line; nil when absent.
    func openForAppend(_ id: String) throws -> (any JournalSink)?
    /// Raw journal bytes, or nil when the session has no journal.
    func contents(_ id: String) throws -> Data?
    /// Ids that have a journal.
    func ids() throws -> [String]
    func remove(_ id: String) throws
    /// Moves a corrupt journal aside (`<id>.jsonl.corrupt`, bytes kept) so it stops blocking.
    func quarantine(_ id: String) throws
    /// Whether `<id>` was set aside by `recover --abandon` (its header then no longer blocks).
    func isQuarantined(_ id: String) -> Bool
    /// The per-install HMAC key (`journal/.key`, 0600), created on first use.
    func hmacKey() throws -> Data
    /// Removes temporary files a SIGKILL left behind. Called under the transaction lock.
    func removeTemporaries()
}

/// An open journal. `append` writes one whole line, then makes it durable (F_FULLFSYNC).
public protocol JournalSink: AnyObject, Sendable {
    func append(_ line: Data) throws
    func sync() throws
}

enum JournalCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func line(_ record: JournalRecord) throws -> Data {
        var data = try encoder().encode(record)
        data.append(0x0a)
        return data
    }

    /// Parses JSONL. A last line without `\n`, or one that does not decode, is torn and ignored.
    /// An undecodable line before the last stops recovery with `journal_corrupt`.
    static func parse(_ data: Data, id: String) throws -> (records: [JournalRecord], tornTail: Bool) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var lines = data.split(separator: 0x0a, omittingEmptySubsequences: false).map { Data($0) }
        var torn = false
        if let last = lines.last, last.isEmpty { lines.removeLast() } else if !lines.isEmpty { torn = true }
        var records: [JournalRecord] = []
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            if isLast && torn { break }
            do {
                let record = try decoder.decode(JournalRecord.self, from: line)
                guard record.v == 1 else { throw MacCtlError.journalCorrupt(snapshotID: id, line: index + 1) }
                records.append(record)
            } catch {
                if isLast { torn = true; break }
                throw MacCtlError.journalCorrupt(snapshotID: id, line: index + 1)
            }
        }
        return (records, torn)
    }

    /// Byte length of the intact prefix (everything before a torn last line).
    static func intactLength(_ data: Data, id: String) throws -> Int {
        let parsed = try parse(data, id: id)
        guard parsed.tornTail else { return data.count }
        guard !parsed.records.isEmpty else { return 0 }
        var newlines = 0
        for (offset, byte) in data.enumerated() where byte == 0x0a {
            newlines += 1
            if newlines == parsed.records.count { return offset + 1 }
        }
        return 0
    }
}

/// `~/Library/Application Support/macctl/journal/<id>.jsonl`; directory 0700, files 0600 created
/// `O_CREAT|O_EXCL|O_APPEND|O_NOFOLLOW`.
public struct FileJournalStore: JournalStore {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Every id becomes a file name, so every entry point goes through here: the snapshot id rule
    /// (letters, digits, `-`, `_`) is enforced, and an id such as `../x` is `snapshot_not_found`
    /// before any path is built (Sam #62 MEDIUM).
    func url(_ id: String, suffix: String = ".jsonl") throws -> URL {
        guard FileSnapshotStore.isSafeID(id) else { throw MacCtlError.snapshotNotFound(id) }
        return directory.appendingPathComponent("\(id)\(suffix)")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        chmod(directory.path, 0o700)
    }

    public func create(_ id: String) throws -> any JournalSink {
        let path = try url(id).path
        try ensureDirectory()
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw MacCtlError.snapshotExists(id) }
            throw Durable.posixError()
        }
        let sink = FileJournalSink(descriptor: descriptor)
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw Durable.posixError() }
        try Durable.fullSync(descriptor)
        try Durable.syncDirectory(directory)
        return sink
    }

    public func openForAppend(_ id: String) throws -> (any JournalSink)? {
        guard let data = try contents(id) else { return nil }
        let keep = try JournalCodec.intactLength(data, id: id)
        let descriptor = open(try url(id).path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Durable.posixError() }
        let sink = FileJournalSink(descriptor: descriptor)
        if keep < data.count {
            guard ftruncate(descriptor, off_t(keep)) == 0 else { throw Durable.posixError() }
            try Durable.fullSync(descriptor)
        }
        return sink
    }

    public func contents(_ id: String) throws -> Data? {
        let path = try url(id).path
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw Durable.posixError()
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            throw MacCtlError.journalCorrupt(snapshotID: id, line: 0)
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    public func ids() throws -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        // Only names `url(_:)` accepts: a stray `a.b.jsonl` (or any non-id name) is skipped with a note
        // on stderr instead of making every unresolvedIDs() call, and so every write, throw (Sam #62).
        var ids: [String] = []
        for name in names where name.hasSuffix(".jsonl") && !name.hasPrefix(".") {
            let id = String(name.dropLast(6))
            if FileSnapshotStore.isSafeID(id) {
                ids.append(id)
            } else {
                FileHandle.standardError.write(Data("macctl: ignoring \(name) in the journal directory (not a session id)\n".utf8))
            }
        }
        return ids
    }

    public func remove(_ id: String) throws {
        if unlink(try url(id).path) != 0 && errno != ENOENT { throw Durable.posixError() }
    }

    public func quarantine(_ id: String) throws {
        let target = try url(id, suffix: ".jsonl.corrupt")
        guard link(try url(id).path, target.path) == 0 else { throw Durable.posixError() }
        try remove(id)
        try Durable.syncDirectory(directory)
    }

    public func isQuarantined(_ id: String) -> Bool {
        guard let target = try? url(id, suffix: ".jsonl.corrupt") else { return false }
        return FileManager.default.fileExists(atPath: target.path)
    }

    public func hmacKey() throws -> Data {
        try ensureDirectory()
        let file = directory.appendingPathComponent(".key")
        if let key = try? Data(contentsOf: file), key.count == 32 { return key }
        var generator = SystemRandomNumberGenerator()
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) })
        // Never create `.key` empty: write a durable 0600 temp, then publish it with link(2), so a
        // kill -9 leaves either no key or a whole one (Sam #62 LOW a).
        let temporary = directory.appendingPathComponent(".key-\(UUID().uuidString).tmp")
        defer { unlink(temporary.path) }
        try Durable.writeExclusive(temporary, key)
        if link(temporary.path, file.path) != 0 {
            guard errno == EEXIST else { throw Durable.posixError() }
            if let existing = try? Data(contentsOf: file), existing.count == 32 { return existing }
            // A short key (left by an older build killed mid-create) was never usable: every
            // caller refused it, so no hash was ever made with it. Replace it atomically.
            guard rename(temporary.path, file.path) == 0 else { throw Durable.posixError() }
        }
        try Durable.syncDirectory(directory)
        return key
    }

    public func removeTemporaries() {
        Durable.removeTemporaries(in: directory, prefixes: [".journal-", ".key-"])
    }
}

final class FileJournalSink: JournalSink, @unchecked Sendable {
    private let descriptor: Int32

    init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    func append(_ line: Data) throws {
        // One write(2) per line with O_APPEND; a kill mid-write leaves a torn last line, never a
        // corrupt middle one.
        try Durable.writeAll(descriptor, line)
    }

    func sync() throws { try Durable.fullSync(descriptor) }
}

/// Journals in memory, with the same parsing (tests).
public final class MemoryJournalStore: JournalStore, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private let key = Data(repeating: 7, count: 32)

    public init() {}

    public func raw(_ id: String) -> Data? { lock.withLock { files[id] } }
    public func setRaw(_ id: String, _ data: Data?) { lock.withLock { files[id] = data } }

    public func create(_ id: String) throws -> any JournalSink {
        try lock.withLock {
            guard files[id] == nil else { throw MacCtlError.snapshotExists(id) }
            files[id] = Data()
        }
        return MemorySink(store: self, id: id)
    }

    public func openForAppend(_ id: String) throws -> (any JournalSink)? {
        guard let data = raw(id) else { return nil }
        let keep = try JournalCodec.intactLength(data, id: id)
        setRaw(id, data.prefix(keep))
        return MemorySink(store: self, id: id)
    }

    public func contents(_ id: String) throws -> Data? { raw(id) }
    public func ids() throws -> [String] { lock.withLock { Array(files.keys) } }
    public func remove(_ id: String) throws { setRaw(id, nil) }
    public private(set) var quarantined: [String: Data] = [:]
    public func quarantine(_ id: String) throws {
        let data = raw(id)
        lock.withLock { quarantined[id] = data }
        setRaw(id, nil)
    }
    public func isQuarantined(_ id: String) -> Bool { lock.withLock { quarantined[id] != nil } }
    public func hmacKey() throws -> Data { key }
    public func removeTemporaries() {}

    fileprivate func append(_ id: String, _ line: Data) {
        lock.withLock { files[id, default: Data()].append(line) }
    }

    private final class MemorySink: JournalSink, @unchecked Sendable {
        let store: MemoryJournalStore
        let id: String
        init(store: MemoryJournalStore, id: String) { self.store = store; self.id = id }
        func append(_ line: Data) throws { store.append(id, line) }
        func sync() throws {}
    }
}

/// Appends records with increasing `seq`, each made durable before `append` returns. The failpoint
/// pair names the "written, not yet synced" and "durable" points of that line.
final class JournalWriter: @unchecked Sendable {
    private let sink: any JournalSink
    private let now: @Sendable () -> Date
    private(set) var nextSeq: Int

    init(sink: any JournalSink, nextSeq: Int, now: @escaping @Sendable () -> Date) {
        self.sink = sink
        self.nextSeq = nextSeq
        self.now = now
    }

    @discardableResult
    func append(_ op: JournalRecord.Op, points: (written: String?, durable: String?) = (nil, nil),
                _ fill: (inout JournalRecord) -> Void = { _ in }) throws -> Int {
        var record = JournalRecord(seq: nextSeq, ts: now(), op: op)
        fill(&record)
        try sink.append(try JournalCodec.line(record))
        nextSeq += 1
        if let written = points.written { Failpoint.hit(written) }
        try sink.sync()
        if let durable = points.durable { Failpoint.hit(durable) }
        return record.seq
    }
}
