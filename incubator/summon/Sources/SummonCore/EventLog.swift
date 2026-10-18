import Foundation

/// One line of Summon's own activity log. macctl changes, checkpoints and crashes already have their own
/// records; this log holds what only Summon (or an agent hook) knows: sessions, themes, undos.
public struct LoggedEvent: Sendable, Equatable, Codable {
    public var time: Date
    /// Dotted kind, see `EventKind`. Kept a string so a newer writer never breaks an older reader.
    public var kind: String
    public var title: String
    public var detail: String?
    /// Links to other records: `checkpoint`, `session`, `folder`, `agent`, `theme`.
    public var refs: [String: String]

    public init(time: Date = Date(), kind: String, title: String, detail: String? = nil, refs: [String: String] = [:]) {
        self.time = time
        self.kind = kind
        self.title = title
        self.detail = detail
        self.refs = refs
    }
}

/// Kinds Summon writes. Hooks may add their own; unknown kinds show as plain events.
public enum EventKind {
    /// `summon agent` opened the agent in a terminal (after its checkpoint).
    public static let agentLaunch = "agent.launch"
    /// An agent session began or ended (written by the Claude Code plugin hooks).
    public static let sessionStart = "session.start"
    public static let sessionEnd = "session.end"
    public static let themeSet = "theme.set"
    public static let sessionUndo = "session.undo"
}

/// Append-only JSON Lines file, newest last. Unreadable lines are skipped, never fatal.
public struct EventLog: Sendable {
    public let file: URL
    /// Lines kept after a trim.
    public let keep: Int
    /// The file is trimmed to `keep` lines once it is larger than this.
    public let maxBytes: Int

    public init(file: URL, keep: Int = 2_000, maxBytes: Int = 1_000_000) {
        self.file = file
        self.keep = keep
        self.maxBytes = maxBytes
    }

    public init(paths: SummonPaths) {
        self.init(file: paths.eventLogFile)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func append(_ event: LoggedEvent) throws {
        let line = try Self.encoder().encode(event) + Data("\n".utf8)
        let manager = FileManager.default
        if !manager.fileExists(atPath: file.path) {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try line.write(to: file, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try trimIfNeeded()
    }

    /// Oldest first.
    public func read() -> [LoggedEvent] {
        guard let text = TextFile.read(file) else { return [] }
        let decoder = Self.decoder()
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? decoder.decode(LoggedEvent.self, from: Data(line.utf8))
        }
    }

    /// Checks the size first so an append never reads the whole file.
    private func trimIfNeeded() throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        guard size > maxBytes, let text = TextFile.read(file) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        try TextFile.write(lines.suffix(keep).joined(separator: "\n") + "\n", to: file)
    }
}
