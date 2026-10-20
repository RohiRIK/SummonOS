import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Optional health check a snapshot store can offer to `doctor`.
/// (Addition to the shared contract; lives here so `Interfaces.swift` stays unchanged.)
public protocol SnapshotStoreDiagnostics: Sendable {
    /// Whether new snapshots can be written, with a one-line detail (the location, or the failure).
    func writableCheck() -> (ok: Bool, detail: String)
}

/// Stores each snapshot as `<directory>/<id>.json` (ISO 8601 dates, sorted keys).
public struct FileSnapshotStore: SnapshotStore, SnapshotStoreDiagnostics {
    public let directory: URL

    /// `~/Library/Application Support/macctl/snapshots`.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/macctl/snapshots", directoryHint: .isDirectory)
    }

    public init(directory: URL = FileSnapshotStore.defaultDirectory) {
        self.directory = directory
    }

    /// Sortable id `yyyyMMdd-HHmmss` (POSIX locale, Gregorian, `timeZone`). When the id is already in
    /// `existing`, appends `-2`, `-3`, ... until it is free.
    public static func makeID(date: Date, existing: Set<String> = [], timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = formatter.string(from: date)
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    public func save(_ snapshot: Snapshot) throws {
        guard Self.isSafeID(snapshot.id) else { throw MacCtlError.snapshotNotFound(snapshot.id) }
        try ensureDirectory()
        let data = try Self.encoder().encode(snapshot)
        // Publish a fully written file with an exclusive hard link. A duplicate id can never replace
        // an older backup, even when a caller did not acquire the transaction lock.
        let temporary = directory.appendingPathComponent(".snapshot-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        Failpoint.hit("snapshot.tmp-written")
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.synchronize()
        Failpoint.hit("snapshot.tmp-synced")
        guard link(temporary.path, fileURL(for: snapshot.id).path) == 0 else {
            if errno == EEXIST { throw MacCtlError.snapshotExists(snapshot.id) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        Failpoint.hit("snapshot.linked")
        try synchronizeDirectory()
        Failpoint.hit("snapshot.dir-synced")
    }

    public func update(_ snapshot: Snapshot) throws {
        _ = try load(id: snapshot.id)
        let data = try Self.encoder().encode(snapshot)
        try data.write(to: fileURL(for: snapshot.id), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL(for: snapshot.id).path)
        let handle = try FileHandle(forWritingTo: fileURL(for: snapshot.id))
        defer { try? handle.close() }
        try handle.synchronize()
        try synchronizeDirectory()
    }

    public func acquireTransaction() async throws -> TransactionLease {
        try ensureDirectory()
        return try await FileTransactionLock.acquire(at: directory.appendingPathComponent(".transaction.lock"))
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func synchronizeDirectory() throws {
        // Persist the new name/atomic replacement as well as the JSON contents before mutating settings.
        let descriptor = open(directory.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Newest first (by `createdAt`, then id). A missing directory means no snapshots.
    public func list() throws -> [Snapshot] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = Self.decoder()
        let snapshots = try files.map { try decoder.decode(Snapshot.self, from: Data(contentsOf: $0)) }
        return snapshots.sorted { a, b in
            a.createdAt != b.createdAt
                ? a.createdAt > b.createdAt
                : a.id.compare(b.id, options: .numeric) == .orderedDescending
        }
    }

    public func load(id: String) throws -> Snapshot {
        guard Self.isSafeID(id) else { throw MacCtlError.snapshotNotFound(id) }
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw MacCtlError.snapshotNotFound(id)
        }
        return try Self.decoder().decode(Snapshot.self, from: Data(contentsOf: url))
    }

    public func writableCheck() -> (ok: Bool, detail: String) {
        let path = directory.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let probe = directory.appending(path: ".write-test-\(UUID().uuidString)")
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return (true, path)
        } catch {
            return (false, "\(path): \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func fileURL(for id: String) -> URL {
        directory.appending(path: "\(id).json", directoryHint: .notDirectory)
    }

    /// Ids become file names: letters, digits, `-` and `_` only (no `/`, no `..`).
    private static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) || scalar == "-" || scalar == "_"
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
