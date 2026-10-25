import Foundation

/// One entry of the Activity timeline, whatever record it came from.
public struct ActivityEvent: Sendable, Equatable, Identifiable, Encodable {
    public enum Category: String, Sendable, Codable, CaseIterable {
        case settings, agent, checkpoint, theme, problem, mac
    }

    /// `<source>:<record id>`, stable across reloads.
    public var id: String
    public var date: Date
    public var category: Category
    /// `setting.change`, `setting.undo`, `checkpoint`, `crash`, or a `LoggedEvent` kind.
    public var kind: String
    public var title: String
    public var detail: String?
    /// Old and new values, for macctl snapshots.
    public var changes: [SettingChange]
    /// `snapshot`, `undoes`, `checkpoint`, `file`, `session`, `folder`, ...
    public var refs: [String: String]

    public init(id: String, date: Date, category: Category, kind: String, title: String, detail: String? = nil,
                changes: [SettingChange] = [], refs: [String: String] = [:]) {
        self.id = id
        self.date = date
        self.category = category
        self.kind = kind
        self.title = title
        self.detail = detail
        self.changes = changes
        self.refs = refs
    }
}

/// A value macctl changed. `from` is nil when the key was unset before.
public struct SettingChange: Sendable, Equatable, Codable {
    public var id: String
    public var from: String?
    public var to: String

    public init(id: String, from: String?, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}

/// A macctl snapshot file as Summon reads it (`<id>.json`: `id`, `createdAt`, `changes`, `undoes`).
/// Read straight from disk: the window refreshes often and spawning macctl each time is slow.
public struct MacctlSnapshot: Sendable, Equatable, Decodable {
    public var id: String
    public var createdAt: Date
    public var changes: [SettingChange]
    /// Set when this snapshot records an undo: the snapshot it reverted.
    public var undoes: String?
    public var status: String? = nil
    public var appliedSettings: [String]? = nil
    public var failure: String? = nil

    public init(id: String, createdAt: Date, changes: [SettingChange], undoes: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.changes = changes
        self.undoes = undoes
    }

    private enum CodingKeys: String, CodingKey { case id, createdAt, changes, undoes, status, appliedSettings, failure }
    private enum ChangeKeys: String, CodingKey { case id, from, to }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        undoes = try container.decodeIfPresent(String.self, forKey: .undoes)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        appliedSettings = try container.decodeIfPresent([String].self, forKey: .appliedSettings)
        failure = try container.decodeIfPresent(String.self, forKey: .failure)
        var list = try container.nestedUnkeyedContainer(forKey: .changes)
        var changes: [SettingChange] = []
        while !list.isAtEnd {
            let change = try list.nestedContainer(keyedBy: ChangeKeys.self)
            changes.append(SettingChange(
                id: try change.decode(String.self, forKey: .id),
                from: try change.decodeIfPresent(Scalar.self, forKey: .from)?.text,
                to: try change.decode(Scalar.self, forKey: .to).text
            ))
        }
        self.changes = changes
    }

    /// macctl writes values as bare JSON scalars (`true`, `40`, `0.5`, `"dark"`).
    struct Scalar: Decodable {
        let text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                text = String(value)
            } else if let value = try? container.decode(Int.self) {
                text = String(value)
            } else if let value = try? container.decode(Double.self) {
                text = String(value)
            } else {
                text = try container.decode(String.self)
            }
        }
    }

    /// Every readable snapshot in `directory`, newest first. Unreadable files are skipped.
    ///
    /// Since macctl's journal (ADR macctl-recovery D2), `snapshots/<id>.json` is a write-once header that
    /// keeps `status: "pending"` forever; the real status is the last `session_end` in
    /// `../journal/<id>.jsonl` (what `macctl snapshot list --json` reports). A header with a sibling
    /// journal therefore takes its status from the journal, read-only (QA R-b).
    public static func load(from directory: URL) -> [MacctlSnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let journal = directory.deletingLastPathComponent().appendingPathComponent("journal", isDirectory: true)
        let snapshots = files.filter { $0.pathExtension == "json" }.compactMap { url -> MacctlSnapshot? in
            guard let data = try? Data(contentsOf: url),
                  var snapshot = try? decoder.decode(MacctlSnapshot.self, from: data) else { return nil }
            if let derived = journalStatus(journal.appendingPathComponent("\(snapshot.id).jsonl")) {
                snapshot.status = derived
            } else if FileManager.default.fileExists(atPath: journal.appendingPathComponent("\(snapshot.id).jsonl.corrupt").path) {
                snapshot.status = "abandoned"  // `macctl recover --abandon <id>` set its journal aside
            }
            return snapshot
        }
        return snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    /// The status a macctl journal implies: the last complete line's `session_end` outcome
    /// (`completed`, `rolled_back`, `undone`, `recovered`), else `pending`; `flagged` when the session
    /// ended but a key was left as it is (`flagged`/`revert_flagged` not later `reverted`: a hand edit,
    /// a third value, or a restore that did not take). nil when there is no journal.
    static func journalStatus(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        struct Line: Decodable { var op: String; var outcome: String?; var ref: Int? }
        // A last line without a newline is torn (being written, or cut by a crash); it is ignored.
        let complete = data.split(separator: 0x0a, omittingEmptySubsequences: false).dropLast().filter { !$0.isEmpty }
        let lines = complete.compactMap { try? JSONDecoder().decode(Line.self, from: Data($0)) }
        guard let last = lines.last, lines.count == complete.count else { return "pending" }
        guard last.op == "session_end" else { return "pending" }
        var flagged: Set<Int> = []
        for line in lines {
            guard let ref = line.ref else { continue }
            if line.op == "flagged" || line.op == "revert_flagged" { flagged.insert(ref) }
            if line.op == "reverted" { flagged.remove(ref) }
        }
        return flagged.isEmpty ? (last.outcome ?? "pending") : "flagged"
    }

    /// How Summon presents a macctl status (decision for #62): `completed`, `undone`/`reverted` (and a
    /// legacy snapshot with no status) are finished; `rolled_back` and `recovered` are informational
    /// ("recovered after interruption", consistent end state); everything else is a Problem:
    /// `pending` (recovery_pending), `failed`, `abandoned`, `flagged`/`revert_flagged` and any unknown status.
    public enum Presentation: Equatable, Sendable { case finished, recovered, problem }

    public var presentation: Presentation {
        switch status ?? "completed" {  // a legacy snapshot with no status is a completed change
        case "completed", "undone", "reverted": return .finished
        case "rolled_back", "recovered": return .recovered
        default: return .problem
        }
    }
}

/// Merges every source into one timeline, newest first. Sorting is by date only: Summon's checkpoint ids
/// are UTC and macctl's snapshot ids are local time, so ids never order across sources.
public enum ActivityFeed {
    public static func build(
        log: [LoggedEvent],
        snapshots: [MacctlSnapshot],
        checkpoints: [Checkpoint],
        crashes: [CrashReport],
        crashDates: [String: Date] = [:]
    ) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        for entry in log {
            events.append(event(from: entry))
        }
        for snapshot in snapshots where !snapshot.changes.isEmpty || snapshot.undoes != nil {
            events.append(event(from: snapshot))
        }
        for checkpoint in checkpoints {
            events.append(ActivityEvent(
                id: "checkpoint:\(checkpoint.id)",
                date: checkpoint.createdAt,
                category: .checkpoint,
                kind: "checkpoint",
                title: "Checkpoint: \(checkpoint.label)",
                detail: checkpointDetail(checkpoint),
                refs: ["checkpoint": checkpoint.id]
            ))
        }
        for report in crashes {
            guard let date = crashDates[report.file] ?? crashDate(report) else { continue }
            let what = [report.signal ?? report.exceptionType].compactMap { $0 }.joined()
            events.append(ActivityEvent(
                id: "crash:\(report.file)",
                date: date,
                category: .problem,
                kind: report.kind.rawValue,
                title: report.kind == .memory
                    ? (report.process.map { "\($0) was stopped: \(report.exceptionType ?? "memory")" } ?? "Memory ran low")
                    : "\(report.program) \(pastTense(report.kind))",
                detail: what.isEmpty ? nil : what,
                refs: ["file": report.file]
            ))
        }
        return events.sorted { a, b in a.date != b.date ? a.date > b.date : a.id > b.id }
    }

    static func event(from entry: LoggedEvent) -> ActivityEvent {
        let category: ActivityEvent.Category
        switch entry.kind {
        case EventKind.themeSet: category = .theme
        case EventKind.sessionUndo: category = .checkpoint
        case let kind where kind.hasPrefix("mac."): category = .mac
        default: category = .agent
        }
        // Not the line number: trimming the log would shift it and lose the selection.
        let millis = Int((entry.time.timeIntervalSince1970 * 1000).rounded())
        return ActivityEvent(
            id: "log:\(millis):\(entry.kind):\(entry.title)",
            date: entry.time,
            category: category,
            kind: entry.kind,
            title: entry.title,
            detail: entry.detail,
            refs: entry.refs
        )
    }

    static func event(from snapshot: MacctlSnapshot) -> ActivityEvent {
        var refs = ["snapshot": snapshot.id]
        if let status = snapshot.status, snapshot.presentation == .problem {
            refs["status"] = status
            let action = snapshot.undoes == nil ? "Settings change" : "Settings undo"
            return ActivityEvent(id: "macctl:\(snapshot.id)", date: snapshot.createdAt, category: .problem,
                                 kind: "setting.\(status)", title: "\(action) \(status)",
                                 detail: snapshot.failure ?? "Recovery journal \(snapshot.id); completed steps: \((snapshot.appliedSettings ?? []).joined(separator: ", "))",
                                 changes: [], refs: refs)
        }
        if let status = snapshot.status, status != "completed" { refs["status"] = status }
        if let undone = snapshot.undoes { refs["undoes"] = undone }
        let title: String
        let kind: String
        if snapshot.presentation == .recovered {
            let what = snapshot.changes.count == 1 ? snapshot.changes[0].id : "\(snapshot.changes.count) settings"
            title = "\(snapshot.undoes == nil ? "Change" : "Undo") of \(what) recovered after interruption"
            kind = "setting.recovered"
        } else if snapshot.status == "undone" || snapshot.status == "reverted" {
            title = snapshot.changes.count == 1 ? "Changed \(snapshot.changes[0].id), then undid it"
                : "Applied \(snapshot.changes.count) settings, then undid them"
            kind = "setting.undone"
        } else if snapshot.undoes != nil {
            title = snapshot.changes.count == 1 ? "Undid \(snapshot.changes[0].id)" : "Undid \(snapshot.changes.count) settings"
            kind = "setting.undo"
        } else if snapshot.changes.count == 1 {
            title = "Changed \(snapshot.changes[0].id)"
            kind = "setting.change"
        } else {
            title = "Applied \(snapshot.changes.count) settings"
            kind = "setting.change"
        }
        let detail = snapshot.changes.count == 1
            ? "\(snapshot.changes[0].from ?? "unset") → \(snapshot.changes[0].to)"
            : snapshot.changes.map(\.id).joined(separator: ", ")
        return ActivityEvent(
            id: "macctl:\(snapshot.id)",
            date: snapshot.createdAt,
            category: .settings,
            kind: kind,
            title: title,
            detail: detail,
            changes: snapshot.changes,
            refs: refs
        )
    }

    static func checkpointDetail(_ checkpoint: Checkpoint) -> String {
        var parts: [String] = []
        parts.append(checkpoint.macctlSnapshot == nil ? "no macctl" : "settings marked")
        parts.append(checkpoint.configCommit == nil ? "~/.config not saved" : "~/.config saved")
        parts.append(contentsOf: checkpoint.problems ?? [])
        return parts.joined(separator: " · ")
    }

    static func pastTense(_ kind: CrashReport.Kind) -> String {
        switch kind {
        case .crash: return "crashed"
        case .hang: return "hung"
        case .panic: return "panicked"
        case .memory: return "ran low on memory"
        case .other: return "reported a problem"
        }
    }

    /// `.ips` timestamps look like `2026-10-17 10:15:00.00 +0000`.
    public static func crashDate(_ report: CrashReport) -> Date? {
        guard let timestamp = report.timestamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: timestamp) { return date }
        }
        return nil
    }

    /// The macctl snapshots taken between two dates, oldest first: what an agent session changed.
    public static func snapshots(_ snapshots: [MacctlSnapshot], from start: Date, to end: Date?) -> [MacctlSnapshot] {
        snapshots
            .filter { snapshot in
                guard snapshot.createdAt >= start else { return false }
                guard let end else { return true }
                return snapshot.createdAt <= end
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

/// Everything the timeline and status read, loaded from disk in one pass (off the main actor in the app).
public struct ActivitySources: Sendable, Equatable {
    public var log: [LoggedEvent]
    public var snapshots: [MacctlSnapshot]
    public var checkpoints: [Checkpoint]
    public var crashes: [CrashReport]
    /// Report file → when it happened (its timestamp, else the file's modification date).
    public var crashDates: [String: Date]
    public var configIsRepo: Bool

    public init(log: [LoggedEvent] = [], snapshots: [MacctlSnapshot] = [], checkpoints: [Checkpoint] = [],
                crashes: [CrashReport] = [], crashDates: [String: Date] = [:], configIsRepo: Bool = false) {
        self.log = log
        self.snapshots = snapshots
        self.checkpoints = checkpoints
        self.crashes = crashes
        self.crashDates = crashDates
        self.configIsRepo = configIsRepo
    }

    public static func load(paths: SummonPaths, crashLimit: Int = 20) -> ActivitySources {
        let checkpointService = CheckpointService(paths: paths, runner: { _, _ in "" }, gitPath: nil, macctlPath: nil)
        let crashes = CrashWatcher(paths: paths).reports(since: nil, limit: crashLimit)
        var crashDates: [String: Date] = [:]
        for report in crashes {
            if let date = ActivityFeed.crashDate(report) {
                crashDates[report.file] = date
            } else if let modified = try? URL(fileURLWithPath: report.file).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                crashDates[report.file] = modified
            }
        }
        return ActivitySources(
            log: EventLog(paths: paths).read(),
            snapshots: MacctlSnapshot.load(from: paths.macctlSnapshots),
            checkpoints: checkpointService.list(),
            crashes: crashes,
            crashDates: crashDates,
            configIsRepo: checkpointService.configIsRepo
        )
    }

    public var events: [ActivityEvent] {
        ActivityFeed.build(log: log, snapshots: snapshots, checkpoints: checkpoints, crashes: crashes, crashDates: crashDates)
    }
}
