import Darwin
import Foundation
import os
import SummonCore

/// `summon task add | list | remove | run`: prompts an agent runs on a schedule, unattended, through launchd.
enum TaskCommands {
    /// A run that takes longer is stopped; its log keeps what it printed.
    static let runLimit: TimeInterval = 30 * 60

    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        switch args.next() {
        case "new":
            // Describe it to the agent; the agent writes the run prompt and calls `task add`.
            let inline = args.flag("--inline")
            let description = args.items.joined(separator: " ")
            try await AgentCommands.launch(prompt: TaskSetup.prompt(description: description), inline: inline, checkpoint: true, context)
        case "add": try await add(&args, context)
        case nil, "list": try list(&args, context)
        case "remove": try await remove(&args, context)
        case "run":
            guard let id = args.next() else { throw CLIError("Usage: summon task run <id>") }
            let operation = Task { try await runTask(id, context) }
            let signals = [SIGTERM, SIGINT].map { number in
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
                source.setEventHandler { operation.cancel() }
                source.resume()
                return source
            }
            defer { for source in signals { source.cancel() } }
            try await operation.value
        default:
            throw CLIError("Usage: summon task new [what you want] | summon task add <prompt> (--at HH:MM [--weekdays] | --every <n>h) [--agent <id>] [--name <name>] | list [--json] | remove <id> | run <id>")
        }
    }

    // MARK: add / list / remove

    @MainActor
    static func add(_ args: inout Arguments, _ context: Context) async throws {
        let lifecycle = try await FileLease.acquire(context.paths.state.appendingPathComponent("locks/task-scheduling.lock"))
        defer { lifecycle.release() }
        let weekdays = args.flag("--weekdays")
        let at = args.option("--at")
        let every = args.option("--every")
        let agentName = args.option("--agent")
        let name = args.option("--name")
        let executionName = args.option("--execution")
        let directoryName = args.option("--directory")
        let prompt = args.items.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { throw CLIError("Usage: summon task add <prompt> (--at HH:MM [--weekdays] | --every <n>h)") }
        let schedule: TaskSchedule
        do {
            schedule = try TaskSchedule.parse(at: at, weekdays: weekdays, every: every)
        } catch let error as TaskSchedule.ParseError {
            throw CLIError(error.description)
        }
        if let agentName {
            guard let agent = AgentRegistry.find(agentName) else { throw CLIError("Unknown agent: \(agentName)") }
            guard agent.headlessPrefix != nil else { throw CLIError("\(agent.name) cannot run unattended yet.") }
        }
        guard let agent = agentName.flatMap(AgentRegistry.find) ?? DefaultAgentStore(paths: context.paths).load(),
              agent.headlessPrefix != nil else { throw CLIError("Choose a supported default agent before scheduling a task.") }
        let policy = ExecutionPolicyStore(paths: context.paths)
        let inferred = try policy.migrate()
        guard let execution = executionName.flatMap(AgentExecutionMode.init(rawValue:)) ?? (executionName == nil ? inferred : nil) else {
            throw CLIError("Use --execution normal or --execution unattended")
        }
        let directory = directoryName.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? context.paths.summonHome
        if directoryName == nil { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError("Task working directory does not exist: \(directory.path)")
        }
        let store = TaskStore(paths: context.paths)
        let title = name ?? String(prompt.prefix(40))
        var created: RecurringTask?
        try store.update { tasks in
            var task = RecurringTask(id: store.newID(for: title), name: title, prompt: prompt,
                                     agent: agent.id, schedule: schedule)
            task.execution = execution
            task.directory = directory.resolvingSymlinksInPath().path
            created = task
            return tasks + [task]
        }
        guard let task = created else { throw CLIError("Task creation failed") }
        do { try await install(task, context) }
        catch {
            let failure = error
            do {
                try await unschedule(task.id, context)
                try store.update { $0.filter { $0.id != task.id } }
            } catch {
                throw CLIError("Task scheduling failed (\(failure)); cleanup also failed (\(error)). The task record was retained for recovery.")
            }
            throw failure
        }
        print("Added \(task.id): \(task.schedule.summary), \(agent.name), \(execution.title), \(task.directory ?? "")")
    }

    struct TaskRow: Encodable {
        let id: String
        let name: String
        let prompt: String
        let agent: String?
        let schedule: String
        let lastRun: Date?
        let lastResult: String?
    }

    static func list(_ args: inout Arguments, _ context: Context) throws {
        let json = args.flag("--json")
        let latest = TaskResults.latestRuns(in: EventLog(paths: context.paths).read())
        let rows = try TaskStore(paths: context.paths).loadValidated().map { task -> TaskRow in
            let last = latest[task.id]
            return TaskRow(id: task.id, name: task.name, prompt: task.prompt, agent: task.agent, schedule: task.schedule.summary,
                           lastRun: last?.event.time, lastResult: last?.outcome.rawValue)
        }
        if json {
            try context.printJSON(rows)
            return
        }
        if rows.isEmpty { print("No tasks. Add one: summon task add \"Check brew updates\" --at 09:00") }
        for row in rows {
            let label = row.lastResult.map { TaskOutcome(rawValue: $0)?.label ?? $0 } ?? ""
            let last = row.lastRun.map { " · last \(label) \($0.formatted(.relative(presentation: .named)))" } ?? ""
            print("\(row.id): \(row.schedule) · \(row.agent ?? "default agent")\(last)\n  \(row.prompt)")
        }
    }

    @MainActor
    static func remove(_ args: inout Arguments, _ context: Context) async throws {
        let lifecycle = try await FileLease.acquire(context.paths.state.appendingPathComponent("locks/task-scheduling.lock"))
        defer { lifecycle.release() }
        guard let id = args.next() else { throw CLIError("Usage: summon task remove <id>") }
        let store = TaskStore(paths: context.paths)
        let tasks = try store.loadValidated()
        guard tasks.contains(where: { $0.id == id }) else { throw CLIError("No task \(id)") }
        try await unschedule(id, context)
        try store.update { $0.filter { $0.id != id } }
        print("Removed \(id)")
    }

    // MARK: launchd

    @MainActor
    static func install(_ task: RecurringTask, _ context: Context) async throws {
        let logDir = context.paths.taskLogs.appendingPathComponent(task.id, isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let summon = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let file = TaskPlist.file(task.id, home: context.paths.home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TaskPlist.data(for: task, summon: summon, path: path, logDir: logDir.path).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try await unschedule(task.id, context, keepFile: true)
        _ = try await context.runner("/bin/launchctl", ["bootstrap", "gui/\(getuid())", file.path])
    }

    /// Missing jobs are harmless; other unload/delete failures must preserve the registry for recovery.
    @MainActor
    static func unschedule(_ id: String, _ context: Context, keepFile: Bool = false) async throws {
        do {
            _ = try await context.runner("/bin/launchctl", ["bootout", "gui/\(getuid())/\(TaskPlist.label(id))"])
        } catch let RunnerError.failed(_, status, output)
            where (status == 3 || status == 113) && (output.localizedCaseInsensitiveContains("no such process") || output.localizedCaseInsensitiveContains("could not find service")) {
            // launchctl reports an already-unloaded service using these status/message pairs.
        }
        if !keepFile {
            let file = TaskPlist.file(id, home: context.paths.home)
            do { try FileManager.default.removeItem(at: file) }
            catch CocoaError.fileNoSuchFile { /* Already removed. */ }
        }
    }

    // MARK: run

    /// How long a run waits for its task's lease: long enough to pass a cleanup that holds it briefly, short enough
    /// that a run overlapping a running one is rejected promptly.
    static let leaseWait: TimeInterval = 2
    /// The fallback banner's bound. It runs after the lease is released, so it never keeps the task busy.
    static let defaultNotificationDeadline: Duration = .seconds(5)

    /// A settled run: its outcome, and whether that outcome was recorded. Notification is separate.
    struct RunReport {
        var record: TaskRunRecord
        var finalization: TaskRunFinalization
        /// What ended a run that did not succeed; rethrown once the run is finalized and announced.
        var error: (any Error)?
    }

    enum Delivery: Equatable {
        /// Summon.app announces it from the event log.
        case byApp
        case posted
        case failed(String)
        case timedOut
        /// Cancelled by the user: nothing to tell them.
        case skipped
    }

    /// Runs a task once, under its lease: one run ID, one terminal record, one log. The lease is released before
    /// the bounded notification, which can never change the outcome.
    @MainActor
    static func runTask(_ id: String, _ context: Context, notificationDeadline: Duration = defaultNotificationDeadline) async throws {
        guard TaskStore.isSafeID(id) else { throw CLIError("Invalid task id") }
        let report: RunReport
        do {
            let lease = try await FileLease.acquire(TaskRunLease.file(context.paths, task: id), timeout: leaseWait)
            defer { lease.release() }
            report = try await execute(id, context)
        }
        let record = report.record
        switch await notify(record, recorded: report.finalization.persistence.isRecorded, context, deadline: notificationDeadline) {
        case .failed(let reason): context.warn("summon: the notification could not be posted: \(reason)")
        case .timedOut: context.warn("summon: the notification was not posted within \(notificationDeadline)")
        case .byApp, .posted, .skipped: break
        }
        for problem in report.finalization.maintenance { context.warn("summon: \(problem)") }
        let log = record.logFile?.path ?? ""
        if let error = report.error {
            if case .failed(let reason) = report.finalization.persistence {
                context.warn("summon: the run \(record.outcome.label), and that result could not be recorded: \(reason)")
            }
            throw error
        }
        if case .failed(let reason) = report.finalization.persistence {
            throw CLIError("The task succeeded, but its result could not be recorded: \(reason). Log: \(log)")
        }
        print("Done. Log: \(log)")
    }

    /// Everything under the task's lease: interrupted-run recovery, preflight, execution and the terminal record.
    /// Throws only when no run can be identified (unreadable registry, unknown task).
    @MainActor
    static func execute(_ id: String, _ context: Context) async throws -> RunReport {
        let paths = context.paths
        let events = EventLog(paths: paths)
        let journal = TaskRunJournal(paths: paths, task: id)
        // A run whose CLI was killed left its marker: record it as interrupted before a new run starts.
        for recovered in TaskRunFinalizer.recoverInterrupted(log: events, journal: journal) {
            if case .failed(let reason) = recovered.persistence { context.warn("summon: an interrupted run could not be recorded: \(reason)") }
            for problem in recovered.maintenance { context.warn("summon: \(problem)") }
        }
        guard let task = try TaskStore(paths: paths).loadValidated().first(where: { $0.id == id }) else { throw CLIError("No task \(id)") }
        // The run's identity (also its log's name) exists before anything that can fail, so every outcome below is
        // recorded against this run, with a log that says why.
        let run = UUID().uuidString
        let logDir = paths.taskLogs.appendingPathComponent(task.id, isDirectory: true)
        let log = logDir.appendingPathComponent(run + ".log")
        var record = TaskRunRecord(run: run, task: task.id, name: task.name, outcome: .failed, started: false, logFile: log)
        let trace = RunTrace.signposter.beginInterval("TaskExecution", id: RunTrace.signposter.makeSignpostID(), "run=\(run, privacy: .public)")
        var failure: (any Error)?
        do {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try journal.begin(TaskRunMarker(run: run, task: task.id, name: task.name, file: log.path))
            let selected: Agent?
            if let id = task.agent {
                guard let pinned = AgentRegistry.find(id) else { throw CLIError("Task's saved agent is unknown: \(id). Recreate the task with a supported agent.") }
                selected = pinned
            } else { selected = DefaultAgentStore(paths: paths).load() }
            guard let agent = selected else { throw CLIError("No agent: set one with summon default agent <name>") }
            record.refs["agent"] = agent.id
            guard let path = context.tools.find(agent.command) else { throw CLIError("\(agent.name) is not installed: \(agent.installHint)") }
            let settings = try AgentSettingsStore(paths: paths).loadValidated()
            let execution = task.execution ?? .unattended // Legacy scheduled tasks retain their original execution choice.
            record.refs["execution"] = execution.rawValue
            guard agent.headlessPrefix != nil else { throw CLIError("\(agent.name) cannot run unattended yet.") }
            let service = CheckpointService(paths: paths, runner: context.runner, gitPath: context.git, macctlPath: context.macctl)
            let (checkpoint, problems) = await service.create(label: "task: \(task.name)")
            try Task.checkCancellation()
            record.refs["checkpoint"] = checkpoint.id
            guard problems.isEmpty else {
                throw CLIError("Checkpoint failed: " + problems.joined(separator: "; ") + ". The task did not start.")
            }
            let folder = task.directory.map { URL(fileURLWithPath: $0) } ?? paths.summonHome
            record.refs["folder"] = folder.path
            if task.directory == nil { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            let brief = SessionBrief(mode: .scheduled(execution, limitMinutes: Int(runLimit / 60)), folder: folder.path,
                                     checkpointID: checkpoint.id, configCaptured: checkpoint.configCommit != nil,
                                     skillFiles: SkillCommands.skillFiles(agent: agent.id, settings: settings))
            let prompt = SessionBrief.scheduledPreamble(name: task.name) + task.prompt + brief.render()
            guard let argv = agent.headless(prompt: prompt, model: settings.model(for: agent.id), execution: execution) else {
                throw CLIError("\(agent.name) cannot run unattended yet.")
            }
            if checkpoint.configCommit == nil { context.warn("Checkpoint covers macctl-supported changes only; ~/.config was not captured.") }
            record.started = true
            let status = try await runLogged(path, Array(argv.dropFirst()), in: folder, log: log, limit: runLimit)
            guard status == 0 else { throw CLIError("Agent exited with \(status). Log: \(log.path)") }
            record.outcome = .done
            // Bounded: the log can be megabytes and its last line arbitrarily long.
            record.detail = LogTail.lastLines(of: log, count: 3)
        } catch {
            failure = error
            record.outcome = TaskOutcome(error: error)
            record.detail = (error as? CLIError)?.message ?? String(describing: error)
        }
        RunTrace.signposter.endInterval("TaskExecution", trace, "outcome=\(record.outcome.rawValue, privacy: .public)")
        record.time = Date()
        return RunReport(record: record, finalization: TaskRunFinalizer.finalize(record, log: events, journal: journal), error: failure)
    }

    /// Output goes only to the bounded log: nothing reads a retained copy (errors and summaries use the log), so
    /// none is kept. Cancellation and timeout clean up the invocation's process group.
    static func runLogged(_ path: String, _ arguments: [String], in folder: URL, log: URL, limit: TimeInterval) async throws -> Int32 {
        var options = ProcessOptions()
        options.timeout = limit
        options.directory = folder
        options.logFile = log
        options.maxOutputBytes = 0
        options.terminateDescendantsOnExit = true
        return try await ProcessExecutor.run(path, arguments, options: options).status
    }

    /// Summon.app announces recorded results from the event log (with Show Log and Ask Agent). The CLI posts a plain
    /// banner (a fixed script, the texts as argv) only when the app cannot: it is not running, or the result never
    /// reached the log. Bounded by `deadline`; the runner is cancelled when it passes.
    static func notify(_ record: TaskRunRecord, recorded: Bool, _ context: Context, deadline: Duration) async -> Delivery {
        let trace = RunTrace.signposter.beginInterval("NotificationSubmission", id: RunTrace.signposter.makeSignpostID(),
                                                      "run=\(record.run, privacy: .public)")
        let delivery = await deliver(record, recorded: recorded, context, deadline: deadline)
        let result: String
        switch delivery {
        case .byApp: result = "app"
        case .posted: result = "posted"
        case .failed: result = "failed"
        case .timedOut: result = "timed-out"
        case .skipped: result = "skipped"
        }
        RunTrace.signposter.endInterval("NotificationSubmission", trace, "\(result, privacy: .public)")
        return delivery
    }

    private static func deliver(_ record: TaskRunRecord, recorded: Bool, _ context: Context, deadline: Duration) async -> Delivery {
        if record.outcome == .cancelled || Task.isCancelled { return .skipped }
        if recorded && AppHealthStore(paths: context.paths).appIsRunning() { return .byApp }
        let runner = context.runner
        let arguments = [
            "-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run",
            "Summon · Task \(record.outcome.label)", record.name,
        ]
        return await withTaskGroup(of: Delivery?.self) { group in
            group.addTask {
                do {
                    _ = try await runner("/usr/bin/osascript", arguments)
                    return .posted
                } catch {
                    return .failed(String(describing: error))
                }
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .timedOut
        }
    }
}
