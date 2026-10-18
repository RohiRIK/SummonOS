import Foundation

/// When a recurring task runs: every so many minutes, or at a clock time on chosen days.
public enum TaskSchedule: Sendable, Equatable, Codable {
    case every(minutes: Int)
    /// Local time. `weekdays` uses launchd's numbering, 1 Monday … 7 Sunday; empty means every day.
    case daily(hour: Int, minute: Int, weekdays: [Int])

    /// Shortest interval a task may repeat at, so a typo cannot start an agent every minute.
    public static let minimumMinutes = 5

    static let dayNames = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// `30m`, `2h`, `1d`.
    public static func parseEvery(_ text: String) -> TaskSchedule? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let unit = trimmed.last, let value = Int(trimmed.dropLast()), value > 0 else { return nil }
        let minutes: Int
        switch unit {
        case "m": minutes = value
        case "h": minutes = value * 60
        case "d": minutes = value * 24 * 60
        default: return nil
        }
        return minutes >= minimumMinutes ? .every(minutes: minutes) : nil
    }

    /// `09:30` plus an optional day list: `mon,wed`, `weekdays`, `weekends`, `daily`.
    public static func parseAt(_ time: String, days: String? = nil) -> TaskSchedule? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        guard let weekdays = weekdays(days) else { return nil }
        return .daily(hour: hour, minute: minute, weekdays: weekdays)
    }

    static func weekdays(_ text: String?) -> [Int]? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return [] }
        switch text {
        case "daily", "every-day", "everyday": return []
        case "weekdays": return [1, 2, 3, 4, 5]
        case "weekends": return [6, 7]
        default: break
        }
        var days: Set<Int> = []
        for name in text.split(separator: ",") {
            let key = String(name.trimmingCharacters(in: .whitespaces).prefix(3))
            guard let index = dayNames.firstIndex(of: key) else { return nil }
            days.insert(index + 1)
        }
        return days.count == 7 ? [] : days.sorted()
    }

    /// "every 2 hours", "weekdays at 09:00".
    public var summary: String {
        switch self {
        case let .every(minutes):
            if minutes % (24 * 60) == 0 { return Self.plural(minutes / (24 * 60), "day") }
            if minutes % 60 == 0 { return Self.plural(minutes / 60, "hour") }
            return Self.plural(minutes, "minute")
        case let .daily(hour, minute, weekdays):
            let time = String(format: "%02d:%02d", hour, minute)
            switch weekdays {
            case []: return "every day at \(time)"
            case [1, 2, 3, 4, 5]: return "weekdays at \(time)"
            case [6, 7]: return "weekends at \(time)"
            default:
                let names = weekdays.map { Self.dayNames[$0 - 1].capitalized }
                return names.joined(separator: ", ") + " at \(time)"
            }
        }
    }

    static func plural(_ count: Int, _ unit: String) -> String {
        count == 1 ? "every \(unit)" : "every \(count) \(unit)s"
    }

    /// The `summon task add` options that make this schedule, for the app and for `task list`.
    public var arguments: [String] {
        switch self {
        case let .every(minutes):
            return ["--every", "\(minutes)m"]
        case let .daily(hour, minute, weekdays):
            var args = ["--at", String(format: "%02d:%02d", hour, minute)]
            if !weekdays.isEmpty {
                args += ["--days", weekdays.map { Self.dayNames[$0 - 1] }.joined(separator: ",")]
            }
            return args
        }
    }
}

/// One recurring task: a prompt the agent runs on a schedule, headless, behind a checkpoint.
public struct AgentTask: Sendable, Equatable, Codable, Identifiable {
    /// kebab-case; names the LaunchAgent and the log folder.
    public var id: String
    public var prompt: String
    public var schedule: TaskSchedule
    /// An agent id; nil runs whichever agent is the default at run time.
    public var agent: String?
    /// Where the agent starts; nil is `~/Summon`.
    public var folder: String?
    public var enabled: Bool
    /// A run still going after this long is stopped.
    public var timeoutMinutes: Int
    public var created: Date

    public static let defaultTimeoutMinutes = 30

    public init(id: String, prompt: String, schedule: TaskSchedule, agent: String? = nil, folder: String? = nil,
                enabled: Bool = true, timeoutMinutes: Int = AgentTask.defaultTimeoutMinutes, created: Date = Date()) {
        self.id = id
        self.prompt = prompt
        self.schedule = schedule
        self.agent = agent
        self.folder = folder
        self.enabled = enabled
        self.timeoutMinutes = timeoutMinutes
        self.created = created
    }

    /// kebab-case, starting with a letter, at most 40 characters.
    public static func isValidID(_ id: String) -> Bool {
        id.count <= 40 && id.range(of: #"^[a-z][a-z0-9]*(-[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }
}

public struct TaskList: Sendable, Equatable, Codable {
    public var tasks: [AgentTask] = []

    public init(tasks: [AgentTask] = []) {
        self.tasks = tasks
    }

    public func find(_ id: String) -> AgentTask? {
        tasks.first { $0.id == id }
    }

    public mutating func upsert(_ task: AgentTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    @discardableResult
    public mutating func remove(_ id: String) -> AgentTask? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        return tasks.remove(at: index)
    }
}

/// `~/.config/summon/tasks.json`, shared by the CLI, the app and agents.
public struct TaskStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    /// A missing file is no tasks. A broken one is an error, so a save never wipes the user's list.
    public func load() throws -> TaskList {
        guard let data = try? Data(contentsOf: paths.tasksFile) else { return TaskList() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TaskList.self, from: data)
    }

    public func save(_ list: TaskList) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try TextFile.write(String(decoding: try encoder.encode(list), as: UTF8.self) + "\n", to: paths.tasksFile)
    }
}

/// The LaunchAgent that runs one task: `~/Library/LaunchAgents/local.macplugins.summon.task.<id>.plist`,
/// whose only job is `summon task run <id> --scheduled`. launchd never starts a job twice at once, and a
/// calendar job missed while the Mac slept runs once on wake.
public enum TaskLaunchAgent {
    public static let labelPrefix = "local.macplugins.summon.task."

    public static func label(_ id: String) -> String { labelPrefix + id }

    public static func file(_ id: String, paths: SummonPaths) -> URL {
        paths.launchAgents.appendingPathComponent(label(id) + ".plist")
    }

    /// The job, as a property list. `summonPath` should outlive app updates (`~/.local/bin/summon`).
    public static func plist(_ task: AgentTask, summonPath: String, paths: SummonPaths) -> [String: Any] {
        let home = paths.home.path
        let log = paths.taskState.appendingPathComponent(task.id, isDirectory: true).appendingPathComponent("launchd.log").path
        var job: [String: Any] = [
            "Label": label(task.id),
            "ProgramArguments": [summonPath, "task", "run", task.id, "--scheduled"],
            "RunAtLoad": false,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            // Each run writes its own log; this one only catches what happens before that (a missing binary).
            "StandardOutPath": log,
            "StandardErrorPath": log,
            "WorkingDirectory": paths.projects.path,
            // launchd's PATH has no Homebrew or ~/.local/bin, where the agents, git and macctl live.
            "EnvironmentVariables": [
                "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            ],
        ]
        switch task.schedule {
        case let .every(minutes):
            job["StartInterval"] = minutes * 60
        case let .daily(hour, minute, weekdays):
            if weekdays.isEmpty {
                job["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
            } else {
                job["StartCalendarInterval"] = weekdays.map { ["Weekday": $0, "Hour": hour, "Minute": minute] }
            }
        }
        return job
    }

    public static func data(_ task: AgentTask, summonPath: String, paths: SummonPaths) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist(task, summonPath: summonPath, paths: paths), format: .xml, options: 0)
    }

    /// Unload first (it fails when nothing is loaded; callers ignore that), then load the job file.
    public static func loadPlan(_ id: String, paths: SummonPaths, uid: UInt32) -> [LaunchPlan] {
        [unloadPlan(id, uid: uid),
         LaunchPlan(executable: "/bin/launchctl", arguments: ["bootstrap", "gui/\(uid)", file(id, paths: paths).path])]
    }

    public static func unloadPlan(_ id: String, uid: UInt32) -> LaunchPlan {
        LaunchPlan(executable: "/bin/launchctl", arguments: ["bootout", "gui/\(uid)/\(label(id))"])
    }

    /// Writes or removes the job file to match the task, then loads or unloads it.
    /// Returns problems instead of throwing on launchctl errors, so a saved task is never lost.
    public static func sync(_ task: AgentTask, summonPath: String, paths: SummonPaths, runner: Runner, uid: UInt32) async throws -> [String] {
        let url = file(task.id, paths: paths)
        guard task.enabled else {
            await remove(task.id, paths: paths, runner: runner, uid: uid)
            return []
        }
        try FileManager.default.createDirectory(at: paths.launchAgents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.taskState.appendingPathComponent(task.id, isDirectory: true),
                                                withIntermediateDirectories: true)
        try data(task, summonPath: summonPath, paths: paths).write(to: url, options: .atomic)
        let plans = loadPlan(task.id, paths: paths, uid: uid)
        _ = try? await runner(plans[0].executable, plans[0].arguments)
        do {
            _ = try await runner(plans[1].executable, plans[1].arguments)
            return []
        } catch {
            return ["could not load \(label(task.id)): \(error)"]
        }
    }

    /// Unloads and deletes the job file of a task that is gone.
    public static func remove(_ id: String, paths: SummonPaths, runner: Runner, uid: UInt32) async {
        let plan = unloadPlan(id, uid: uid)
        _ = try? await runner(plan.executable, plan.arguments)
        try? FileManager.default.removeItem(at: file(id, paths: paths))
    }
}

/// How one run ended.
public enum TaskRunStatus: String, Sendable, Codable {
    case ok, failed, timeout
    /// Not started: no agent, the agent has no headless mode, or the last run is still going.
    case skipped
}

public struct TaskRunResult: Sendable, Equatable {
    public var status: TaskRunStatus
    /// What went wrong, or the end of the agent's answer.
    public var summary: String
    public var log: URL?
    public var checkpoint: String?
}

/// Runs one process with its output going straight to a file, in `directory`, stopped after `timeout` seconds.
public typealias TaskExecutor = @Sendable (_ executable: String, _ arguments: [String], _ directory: URL, _ log: URL,
                                           _ timeout: TimeInterval) async throws -> TaskExit

public struct TaskExit: Sendable, Equatable {
    public var status: Int32
    public var timedOut: Bool

    public init(status: Int32, timedOut: Bool) {
        self.status = status
        self.timedOut = timedOut
    }
}

/// `summon task run`: checkpoint, run the agent headless, keep its output, record the result in Activity.
public struct TaskRunner: Sendable {
    public let paths: SummonPaths
    public let runner: Runner
    public let execute: TaskExecutor
    public let tools: ToolLocator
    public let gitPath: String?
    public let macctlPath: String?

    /// Logs kept per task; older ones are deleted after each run.
    public static let keptLogs = 20

    public init(paths: SummonPaths, runner: @escaping Runner, execute: @escaping TaskExecutor, tools: ToolLocator,
                gitPath: String?, macctlPath: String?) {
        self.paths = paths
        self.runner = runner
        self.execute = execute
        self.tools = tools
        self.gitPath = gitPath
        self.macctlPath = macctlPath
    }

    func folder(_ id: String) -> URL { paths.taskState.appendingPathComponent(id, isDirectory: true) }

    /// `footer` lists the skill files the agent may use (the same text `summon agent prompt` adds).
    public func run(_ task: AgentTask, footer: String = "", now: Date = Date()) async -> TaskRunResult {
        let result = await perform(task, footer: footer, now: now)
        var refs = ["task": task.id, "status": result.status.rawValue]
        refs["checkpoint"] = result.checkpoint
        refs["log"] = result.log?.path
        let title: String
        switch result.status {
        case .ok: title = "Task \(task.id) finished"
        case .failed: title = "Task \(task.id) failed"
        case .timeout: title = "Task \(task.id) timed out"
        case .skipped: title = "Task \(task.id) skipped"
        }
        // Stamped when the run ends, so the app (which notifies about runs newer than its last look) sees it.
        try? EventLog(paths: paths).append(LoggedEvent(time: Date(), kind: EventKind.taskRun, title: title,
                                                       detail: result.summary.isEmpty ? nil : result.summary, refs: refs))
        return result
    }

    func perform(_ task: AgentTask, footer: String, now: Date) async -> TaskRunResult {
        let agent: Agent?
        if let id = task.agent {
            agent = AgentRegistry.find(id)
        } else {
            agent = DefaultAgentStore(paths: paths).load()
        }
        guard let agent else {
            return TaskRunResult(status: .skipped, summary: task.agent.map { "Unknown agent \($0)" } ?? "No default agent chosen (summon default agent <name>)")
        }
        let model = AgentSettingsStore(paths: paths).load().model(for: agent.id)
        guard let argv = agent.headlessArgv(prompt: task.prompt + footer, model: model) else {
            return TaskRunResult(status: .skipped, summary: "\(agent.name) has no headless mode Summon can schedule; use Claude Code, Codex or Copilot")
        }
        guard let agentPath = tools.find(agent.command) else {
            return TaskRunResult(status: .skipped, summary: "\(agent.name) is not installed (\(agent.installHint))")
        }

        let lock = folder(task.id).appendingPathComponent("running")
        guard Self.acquire(lock) else {
            return TaskRunResult(status: .skipped, summary: "The previous run is still going")
        }
        defer { try? FileManager.default.removeItem(at: lock) }

        let service = CheckpointService(paths: paths, runner: runner, gitPath: gitPath, macctlPath: macctlPath)
        let (checkpoint, _) = await service.create(label: "task: \(task.id)", now: now)

        let directory = task.folder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? paths.projects
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = folder(task.id).appendingPathComponent(Checkpoint.makeID(now) + ".log")
        defer { pruneLogs(task.id) }
        do {
            let exit = try await execute(agentPath, Array(argv.dropFirst()), directory, log, TimeInterval(task.timeoutMinutes * 60))
            let tail = Self.tail(of: log)
            if exit.timedOut {
                return TaskRunResult(status: .timeout, summary: "Stopped after \(task.timeoutMinutes) minutes", log: log, checkpoint: checkpoint.id)
            }
            return TaskRunResult(status: exit.status == 0 ? .ok : .failed,
                                 summary: exit.status == 0 ? tail : "Exit \(exit.status)" + (tail.isEmpty ? "" : ": " + tail),
                                 log: log, checkpoint: checkpoint.id)
        } catch {
            return TaskRunResult(status: .failed, summary: String(describing: error), log: log, checkpoint: checkpoint.id)
        }
    }

    /// Creates the lock file holding this process's id; a lock left by a process that is gone is taken over.
    static func acquire(_ lock: URL) -> Bool {
        let manager = FileManager.default
        try? manager.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        // EPERM means the process exists but belongs to someone else: still alive.
        if let text = TextFile.firstLine(lock), let pid = Int32(text), pid != getpid(), kill(pid, 0) == 0 || errno == EPERM {
            return false
        }
        return manager.createFile(atPath: lock.path, contents: Data("\(getpid())\n".utf8))
    }

    /// The last non-empty lines of a run's output, at most 300 characters, for Activity and the notification.
    static func tail(of log: URL, limit: Int = 300) -> String {
        guard let text = TextFile.read(log) else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return "…" + String(trimmed.suffix(limit))
    }

    func pruneLogs(_ id: String) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: folder(id), includingPropertiesForKeys: nil) else { return }
        // Run ids are timestamps, so name order is time order.
        let logs = files.filter { $0.pathExtension == "log" && $0.lastPathComponent != "launchd.log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in logs.dropLast(Self.keptLogs) {
            try? manager.removeItem(at: old)
        }
    }

    /// The newest run's output file, if any.
    public func latestLog(_ id: String) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(id), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "log" && $0.lastPathComponent != "launchd.log" }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// The repeat choices the Settings editor offers; the CLI takes any `TaskSchedule`.
public enum TaskRepeat: String, Sendable, CaseIterable, Identifiable {
    case hourly, daily, weekdays

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hourly: return "Every few hours"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        }
    }

    public func schedule(hours: Int, hour: Int, minute: Int) -> TaskSchedule {
        switch self {
        case .hourly: return .every(minutes: max(1, hours) * 60)
        case .daily: return .daily(hour: hour, minute: minute, weekdays: [])
        case .weekdays: return .daily(hour: hour, minute: minute, weekdays: [1, 2, 3, 4, 5])
        }
    }
}

extension EventLog {
    /// The newest `task.run` event of each task, by task id.
    public func lastTaskRuns() -> [String: LoggedEvent] {
        var runs: [String: LoggedEvent] = [:]
        for event in read() where event.kind == EventKind.taskRun {
            if let id = event.refs["task"] { runs[id] = event }
        }
        return runs
    }
}
