import Foundation

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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(snapshot)
        try data.write(to: fileURL(for: snapshot.id), options: .atomic)
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
