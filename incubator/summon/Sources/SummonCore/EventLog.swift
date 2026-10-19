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
    /// `summon project new` made a project in ~/Summon; `summon project repo` gave it a private repo.
    public static let projectNew = "project.new"
    public static let projectRepo = "project.repo"
    /// A recurring task ran (`summon task run`).
    public static let taskDone = "task.done"
    public static let taskFailed = "task.failed"
    /// `summon clean` moved old files from ~/Summon to the Trash.
    public static let summonClean = "summon.clean"
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

/// Turns a Claude Code `SessionStart` / `SessionEnd` hook payload (JSON on stdin) into a log entry.
public enum SessionHook {
    struct Payload: Decodable {
        var session_id: String?
        var cwd: String?
        /// SessionStart: `startup`, `resume`, `clear`, `compact`.
        var source: String?
        /// SessionEnd: `clear`, `logout`, `prompt_input_exit`, `other`, ...
        var reason: String?
    }

    /// `phase` is `start` or `end`. Nil when there is nothing to record: an unknown phase, or a
    /// compaction (the same session carries on).
    public static func event(phase: String, payload: String, agent: String = "Claude Code", now: Date = Date()) -> LoggedEvent? {
        let decoded = try? JSONDecoder().decode(Payload.self, from: Data(payload.utf8))
        var refs: [String: String] = [:]
        refs["session"] = decoded?.session_id
        refs["folder"] = decoded?.cwd
        switch phase {
        case "start":
            if decoded?.source == "compact" { return nil }
            let resumed = decoded?.source == "resume"
            return LoggedEvent(time: now, kind: EventKind.sessionStart,
                               title: resumed ? "\(agent) session resumed" : "\(agent) session started",
                               detail: decoded?.cwd, refs: refs)
        case "end":
            return LoggedEvent(time: now, kind: EventKind.sessionEnd, title: "\(agent) session ended",
                               detail: decoded?.reason.map { "Reason: \($0)" }, refs: refs)
        default:
            return nil
        }
    }
}
