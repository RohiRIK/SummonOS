import Darwin
import Foundation
import os

/// Lifecycle timing for Instruments and the runtime audit: run IDs, outcomes and elapsed time only, never prompts,
/// paths or log text.
public enum RunTrace {
    public static let signposter = OSSignposter(subsystem: "local.macplugins.summon", category: "run")
}

/// How one scheduled run ended. The raw value is stored in a terminal record's `refs["outcome"]` and reported by
/// `TaskResults.latest`. Only `done` is a success.
public enum TaskOutcome: String, Sendable, Codable, CaseIterable {
    case done
    case failed
    case cancelled
    case timedOut = "timed-out"
    case interrupted

    /// For titles and sentences: `Task timed out: Brew`.
    public var label: String { self == .timedOut ? "timed out" : rawValue }

    /// Success is `task.done`; every other outcome is a `task.failed` record carrying its outcome.
    public var eventKind: String { self == .done ? EventKind.taskDone : EventKind.taskFailed }

    /// The outcome an error that ended a run stands for.
    public init(error: any Error) {
        if error is CancellationError {
            self = .cancelled
        } else if let runner = error as? RunnerError, case .timedOut = runner {
            self = .timedOut
        } else {
            self = .failed
        }
    }
}

/// Reads task results from the event log. The only projection of task state: every reader uses it.
public enum TaskResults {
    /// A terminal record and the run it belongs to.
    public struct Terminal: Sendable, Equatable {
        public let task: String
        public let run: String?
        public let outcome: TaskOutcome
        public let event: LoggedEvent
    }

    /// The outcome a record states, nil for anything that is not a terminal task record. `task.failed` without an
    /// outcome (older logs, or an outcome this version does not know) is a failure.
    public static func outcome(of event: LoggedEvent) -> TaskOutcome? {
        switch event.kind {
        case EventKind.taskDone:
            return .done
        case EventKind.taskFailed:
            guard let outcome = event.refs["outcome"].flatMap(TaskOutcome.init(rawValue:)), outcome != .done else { return .failed }
            return outcome
        default:
            return nil
        }
    }

    /// The run a record belongs to: `refs["run"]`, else the UUID name of its run log (records written before run
    /// identity existed). Nil for records with neither; those count individually.
    public static func runID(of event: LoggedEvent) -> String? {
        if let run = event.refs["run"], !run.isEmpty { return run }
        guard let file = event.refs["file"], !file.isEmpty else { return nil }
        let url = URL(fileURLWithPath: file)
        let stem = url.deletingPathExtension().lastPathComponent
        guard url.pathExtension == "log", UUID(uuidString: stem) != nil else { return nil }
        return stem
    }

    /// Terminal task records in log (commit) order, one per run: a later record of a run already seen (a replay or
    /// a recovery after the run had finished) is ignored.
    public static func terminals(in events: [LoggedEvent]) -> [Terminal] {
        var seen = Set<String>()
        var result: [Terminal] = []
        for event in events {
            guard let task = event.refs["task"], !task.isEmpty, let outcome = outcome(of: event) else { continue }
            let run = runID(of: event)
            if let run, !seen.insert(run).inserted { continue }
            result.append(Terminal(task: task, run: run, outcome: outcome, event: event))
        }
        return result
    }

    /// Each task's most recently committed run.
    public static func latestRuns(in events: [LoggedEvent]) -> [String: Terminal] {
        var result: [String: Terminal] = [:]
        for terminal in terminals(in: events) { result[terminal.task] = terminal }
        return result
    }

    /// Task ID → `TaskOutcome.rawValue` of its most recent run.
    public static func latest(in events: [LoggedEvent]) -> [String: String] {
        latestRuns(in: events).mapValues(\.outcome.rawValue)
    }
}

/// The end of a run log, read without loading the whole file.
public enum LogTail {
    /// The last `count` non-blank lines within the final `maxBytes` bytes. A line cut by the byte bound starts with
    /// `…`; a cut never splits a UTF-8 character at the start.
    public static func lastLines(of file: URL, count: Int, maxBytes: Int = 4_096) -> String? {
        guard count > 0, maxBytes > 0, let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        do { try handle.seek(toOffset: start) } catch { return nil }
        guard var bytes = (try? handle.read(upToCount: Int(end - start))) ?? nil else { return nil }
        if start > 0 {
            let continuation = bytes.prefix(3).prefix { $0 & 0xC0 == 0x80 }.count
            bytes = bytes.dropFirst(continuation)
        }
        let text = String(decoding: bytes, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if start > 0, !text.hasPrefix("\n"), let first = lines.first, !first.isEmpty { lines[0] = "…" + first }
        let kept = lines.filter { !$0.isEmpty }.suffix(count)
        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }
}

/// The per-task run lease: held for a run's execution and finalization, and by cleanup before it moves task logs.
public enum TaskRunLease {
    public static func file(_ paths: SummonPaths, task: String) -> URL {
        paths.state.appendingPathComponent("locks/task-\(task).lock")
    }
}

/// A run marker survives until its terminal record is committed and the marker can be removed; a leftover may
/// represent either an interrupted run or a committed run whose marker cleanup was interrupted.
public struct TaskRunMarker: Sendable, Equatable, Codable {
    public var run: String
    public var task: String
    public var name: String
    public var file: String?
    public var started: Date

    public init(run: String, task: String, name: String, file: String?, started: Date = Date()) {
        self.run = run
        self.task = task
        self.name = name
        self.file = file
        self.started = started
    }
}

/// Active-run markers, `state/runs/<task>/<run>.json`. Only touched under the task's run lease.
public struct TaskRunJournal: Sendable {
    public let paths: SummonPaths
    public let task: String

    public init(paths: SummonPaths, task: String) {
        self.paths = paths
        self.task = task
    }

    public var folder: URL { paths.state.appendingPathComponent("runs/\(task)", isDirectory: true) }

    func file(_ run: String) -> URL { folder.appendingPathComponent(run + ".json") }

    public func begin(_ marker: TaskRunMarker) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try TextFile.write(String(decoding: try encoder.encode(marker), as: UTF8.self) + "\n", to: file(marker.run))
    }

    /// Runs that started and never finalized, oldest first. An unreadable marker throws; it is preserved.
    public func pending() throws -> [TaskRunMarker] {
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: folder.path) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try names.filter { $0.hasSuffix(".json") }.sorted().map { name in
            try decoder.decode(TaskRunMarker.self, from: Data(contentsOf: folder.appendingPathComponent(name)))
        }.sorted { $0.started < $1.started }
    }

    public func end(run: String) throws {
        do { try FileManager.default.removeItem(at: file(run)) }
        catch CocoaError.fileNoSuchFile { /* Never begun, or already ended. */ }
    }
}

/// The single terminal record of a run.
public struct TaskRunRecord: Sendable, Equatable {
    public var run: String
    public var task: String
    public var name: String
    public var outcome: TaskOutcome
    /// False when the run stopped before the agent was started.
    public var started: Bool
    public var detail: String?
    public var logFile: URL?
    /// Further links: agent, checkpoint, execution, folder.
    public var refs: [String: String]
    public var time: Date

    public init(run: String, task: String, name: String, outcome: TaskOutcome, started: Bool, detail: String? = nil,
                logFile: URL? = nil, refs: [String: String] = [:], time: Date = Date()) {
        self.run = run
        self.task = task
        self.name = name
        self.outcome = outcome
        self.started = started
        self.detail = detail
        self.logFile = logFile
        self.refs = refs
        self.time = time
    }

    public var title: String {
        started || outcome == .interrupted ? "Task \(outcome.label): \(name)" : "Task stopped: \(name)"
    }

    /// The record as one event, fitted to the event-size limit. The log reference is set only when the log exists.
    public func event() throws -> LoggedEvent {
        var refs = self.refs
        refs["task"] = task
        refs["run"] = run
        refs["outcome"] = outcome.rawValue
        refs["file"] = logFile.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0.path : nil }
        return try LoggedEvent(time: time, kind: outcome.eventKind, title: title, detail: detail, refs: refs).fitted()
    }
}

/// Whether a run's terminal record reached the event log.
public enum TaskRunPersistence: Sendable, Equatable {
    case recorded
    /// Nothing was committed. The execution outcome stands; it is reported, never retried by rerunning the task.
    case failed(String)

    public var isRecorded: Bool { self == .recorded }
}

/// What finalization did, kept apart from the run's outcome: neither changes it.
public struct TaskRunFinalization: Sendable, Equatable {
    public var persistence: TaskRunPersistence
    /// Problems after the outcome was settled: log annotation, event-log retention, the active-run marker.
    public var maintenance: [String]
}

public enum TaskRunFinalizer {
    /// Appends the run's terminal record once (a receipt is a commit; a throw committed nothing, and nothing is
    /// retried), notes a non-success in the run log so the log says why, then closes the active-run marker.
    public static func finalize(_ record: TaskRunRecord, log: EventLog, journal: TaskRunJournal,
                                keepMarkerUnlessRecorded: Bool = false) -> TaskRunFinalization {
        var maintenance: [String] = []
        if record.outcome != .done, let file = record.logFile {
            let note = "\nsummon: \(record.title)" + (record.detail.map { "\nsummon: \($0)" } ?? "") + "\n"
            do { try appendNote(note, to: file) }
            catch { maintenance.append("could not note the result in \(file.path): \(error)") }
        }
        let persistence: TaskRunPersistence
        let trace = RunTrace.signposter.beginInterval("ResultPersistence", id: RunTrace.signposter.makeSignpostID(),
                                                      "run=\(record.run, privacy: .public)")
        do {
            let receipt = try log.append(record.event())
            if let failure = receipt.maintenanceFailure { maintenance.append("event log maintenance failed: \(failure)") }
            persistence = .recorded
        } catch {
            persistence = .failed(String(describing: error))
        }
        let result = persistence.isRecorded ? "recorded" : "failed"
        RunTrace.signposter.endInterval("ResultPersistence", trace, "\(result, privacy: .public)")
        if persistence.isRecorded || !keepMarkerUnlessRecorded {
            do { try journal.end(run: record.run) }
            catch { maintenance.append("could not clear the active-run marker: \(error)") }
        }
        return TaskRunFinalization(persistence: persistence, maintenance: maintenance)
    }

    /// Records runs whose CLI died before finalizing as interrupted. A marker stays until its record is committed.
    public static func recoverInterrupted(log: EventLog, journal: TaskRunJournal, now: Date = Date()) -> [TaskRunFinalization] {
        let markers: [TaskRunMarker]
        do { markers = try journal.pending() }
        catch {
            return [TaskRunFinalization(persistence: .failed("unreadable active-run marker in \(journal.folder.path): \(error)"),
                                        maintenance: [])]
        }
        // The append may have committed before the previous process could remove its marker.
        // Do not turn that settled run into a second, contradictory terminal outcome.
        let committed = Set(TaskResults.terminals(in: log.read()).compactMap { terminal in
            terminal.run.map { "\(terminal.event.refs["task"] ?? ""):\($0)" }
        })
        return markers.map { marker in
            if committed.contains("\(marker.task):\(marker.run)") {
                do {
                    try journal.end(run: marker.run)
                    return TaskRunFinalization(persistence: .recorded, maintenance: [])
                } catch {
                    return TaskRunFinalization(persistence: .recorded,
                                               maintenance: ["could not clear the active-run marker: \(error)"])
                }
            }
            let record = TaskRunRecord(run: marker.run, task: marker.task, name: marker.name, outcome: .interrupted, started: true,
                                       detail: "The run ended without a result: Summon was stopped before it finished. The log may be incomplete.",
                                       logFile: marker.file.map { URL(fileURLWithPath: $0) }, time: now)
            return finalize(record, log: log, journal: journal, keepMarkerUnlessRecorded: true)
        }
    }

    static func appendNote(_ text: String, to file: URL) throws {
        let fd = open(file.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data(text.utf8))
    }
}
