import Darwin
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
    /// `summon agent` could not open the terminal; the detail says what to do.
    public static let agentLaunchFailed = "agent.launch.failed"
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

/// Why an event could not be appended. A thrown append committed nothing; a returned receipt is a commit.
public enum EventLogError: Error, Equatable, CustomStringConvertible {
    case tooLarge(bytes: Int, limit: Int)

    public var description: String {
        switch self {
        case let .tooLarge(bytes, limit): return "event is \(bytes) bytes encoded; the limit is \(limit)"
        }
    }
}

extension LoggedEvent {
    /// Bytes this event takes as one log line, newline included.
    public func encodedLineBytes() throws -> Int {
        try EventLog.encoder().encode(self).count + 1
    }

    /// This event shortened until its whole encoded line (escaping, Unicode and refs included) fits `limit`.
    /// The detail keeps its end, where a run's summary is; then the title keeps its start. Refs are never
    /// changed: when they alone are too large, this throws rather than recording a misleading event.
    public func fitted(to limit: Int = EventLog.maxEventBytes) throws -> LoggedEvent {
        if try encodedLineBytes() <= limit { return self }
        var candidate = self
        if let detail {
            candidate.detail = nil
            if try candidate.encodedLineBytes() <= limit {
                let kept = try Self.longest(detail.count, limit) { count in
                    var probe = self
                    probe.detail = "…" + String(detail.suffix(count))
                    return probe
                }
                if kept > 0 { candidate.detail = "…" + String(detail.suffix(kept)) }
                return candidate
            }
        }
        let title = candidate.title
        let base = candidate
        let kept = try Self.longest(title.count, limit) { count in
            var probe = base
            probe.title = String(title.prefix(count)) + "…"
            return probe
        }
        candidate.title = String(title.prefix(kept)) + "…"
        guard try candidate.encodedLineBytes() <= limit else {
            throw EventLogError.tooLarge(bytes: try candidate.encodedLineBytes(), limit: limit)
        }
        return candidate
    }

    /// The largest count in 0...upper whose probe fits; encoded size grows with the count.
    private static func longest(_ upper: Int, _ limit: Int, _ probe: (Int) -> LoggedEvent) throws -> Int {
        var low = 0, high = upper
        while low < high {
            let middle = (low + high + 1) / 2
            if try probe(middle).encodedLineBytes() <= limit { low = middle } else { high = middle - 1 }
        }
        return low
    }
}

/// Append-only JSON Lines file, newest last. Unreadable lines are skipped, never fatal.
public struct EventLog: Sendable {
    /// The largest line, newline included, `append` accepts. Use `LoggedEvent.fitted()` for unbounded text.
    public static let maxEventBytes = 65_536

    /// Proof that an event is in the log. Never append the same event again after receiving one.
    public struct AppendReceipt: Sendable, Equatable {
        /// Byte offset of the line's first byte when it was written (before any trim).
        public let offset: UInt64
        /// Bytes of the line, newline included.
        public let length: Int
        /// Retention maintenance ran after the commit and rewrote the file (a new file identity).
        public let trimmed: Bool
        /// Retention maintenance failed after the commit. The event is recorded regardless.
        public let maintenanceFailure: String?
    }

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

    /// Writes one line under the log's lease. A throw means nothing was committed (a partial write is rolled
    /// back); a receipt means the line is in the file, even when the retention trim afterwards failed.
    @discardableResult
    public func append(_ event: LoggedEvent) throws -> AppendReceipt {
        var line = try Self.encoder().encode(event)
        line.append(0x0A)
        guard line.count <= Self.maxEventBytes else { throw EventLogError.tooLarge(bytes: line.count, limit: Self.maxEventBytes) }
        let lease = try FileLease.acquireSync(file.appendingPathExtension("lock"))
        defer { lease.release() }
        let fd = open(file.path, O_RDWR | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Self.posixError(errno) }
        defer { close(fd) }
        var info = stat()
        guard fchmod(fd, 0o600) == 0, fstat(fd, &info) == 0 else { throw Self.posixError(errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw StateFileError.invalid(file, "the event log must be a regular file") }
        let start = UInt64(info.st_size)
        var offset = start
        // A writer that died mid-line left no newline; start a fresh line so this event stays readable.
        if start > 0 {
            var last: UInt8 = 0
            if pread(fd, &last, 1, off_t(start - 1)) == 1, last != 0x0A {
                line.insert(0x0A, at: line.startIndex)
                offset += 1
            }
        }
        do {
            try Self.writeAll(fd, line)
        } catch {
            // Never leave half an event behind: a failed append records nothing.
            _ = ftruncate(fd, off_t(start))
            throw error
        }
        let length = line.count - Int(offset - start)
        var trimmed = false
        var failure: String?
        do { trimmed = try trimIfNeeded(size: start + UInt64(line.count)) }
        catch { failure = String(describing: error) }
        return AppendReceipt(offset: offset, length: length, trimmed: trimmed, maintenanceFailure: failure)
    }

    /// Oldest first.
    public func read() -> [LoggedEvent] {
        guard let text = TextFile.read(file) else { return [] }
        let decoder = Self.decoder()
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? decoder.decode(LoggedEvent.self, from: Data(line.utf8))
        }
    }

    /// Uses the size the append just produced, so an append never reads the whole file below the threshold.
    private func trimIfNeeded(size: UInt64) throws -> Bool {
        guard size > UInt64(max(0, maxBytes)) else { return false }
        guard let text = TextFile.read(file) else { throw StateFileError.invalid(file, "could not read it to trim") }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var retained: [Substring] = []
        var bytes = 0
        for line in lines.suffix(max(0, keep)).reversed() {
            let count = line.utf8.count + 1
            guard bytes + count <= maxBytes else { break }
            retained.append(line)
            bytes += count
        }
        let result = retained.reversed().joined(separator: "\n")
        try TextFile.write(result.isEmpty ? "" : result + "\n", to: file)
        return true
    }

    private static func writeAll(_ descriptor: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posixError(errno)
                }
                guard count > 0 else { throw posixError(EIO) }
                written += count
            }
        }
    }

    private static func posixError(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
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
