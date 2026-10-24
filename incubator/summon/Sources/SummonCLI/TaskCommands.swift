import Darwin
import Foundation
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
        defer { lifecycle.hold() }
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
        let events = EventLog(paths: context.paths).read()
        let rows = try TaskStore(paths: context.paths).loadValidated().map { task -> TaskRow in
            let last = events.last { $0.refs["task"] == task.id }
            return TaskRow(id: task.id, name: task.name, prompt: task.prompt, agent: task.agent, schedule: task.schedule.summary,
                           lastRun: last?.time, lastResult: last.map { $0.kind == EventKind.taskFailed ? "failed" : "done" })
        }
        if json {
            try context.printJSON(rows)
            return
        }
        if rows.isEmpty { print("No tasks. Add one: summon task add \"Check brew updates\" --at 09:00") }
        for row in rows {
            let last = row.lastRun.map { " · last \(row.lastResult ?? "") \($0.formatted(.relative(presentation: .named)))" } ?? ""
            print("\(row.id): \(row.schedule) · \(row.agent ?? "default agent")\(last)\n  \(row.prompt)")
        }
    }

    @MainActor
    static func remove(_ args: inout Arguments, _ context: Context) async throws {
        let lifecycle = try await FileLease.acquire(context.paths.state.appendingPathComponent("locks/task-scheduling.lock"))
        defer { lifecycle.hold() }
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

    @MainActor
    static func runTask(_ id: String, _ context: Context) async throws {
        guard TaskStore.isSafeID(id) else { throw CLIError("Invalid task id") }
        let lease = try FileLease.acquireSync(context.paths.state.appendingPathComponent("locks/task-\(id).lock"), timeout: 0)
        defer { lease.hold() }
        guard let task = try TaskStore(paths: context.paths).loadValidated().first(where: { $0.id == id }) else { throw CLIError("No task \(id)") }
        let selected: Agent?
        if let id = task.agent {
            guard let pinned = AgentRegistry.find(id) else { throw CLIError("Task's saved agent is unknown: \(id). Recreate the task with a supported agent.") }
            selected = pinned
        } else { selected = DefaultAgentStore(paths: context.paths).load() }
        guard let agent = selected else { throw CLIError("No agent: set one with summon default agent <name>") }
        guard let path = context.tools.find(agent.command) else { throw CLIError("\(agent.name) is not installed: \(agent.installHint)") }
        let settings = try AgentSettingsStore(paths: context.paths).loadValidated()
        let execution = task.execution ?? .unattended // Legacy scheduled tasks retain their original execution choice.
        guard agent.headlessPrefix != nil else { throw CLIError("\(agent.name) cannot run unattended yet.") }
        let service = CheckpointService(paths: context.paths, runner: context.runner, gitPath: context.git, macctlPath: context.macctl)
        let (checkpoint, problems) = await service.create(label: "task: \(task.name)")
        var refs = ["task": task.id, "agent": agent.id, "checkpoint": checkpoint.id, "execution": execution.rawValue]
        guard problems.isEmpty else {
            ActivityCommands.record(LoggedEvent(kind: EventKind.taskFailed, title: "Task stopped: \(task.name)",
                                               detail: "Checkpoint failed: " + problems.joined(separator: "; "), refs: refs), context)
            throw CLIError("Task did not start because its checkpoint failed: " + problems.joined(separator: "; "))
        }
        let folder = task.directory.map { URL(fileURLWithPath: $0) } ?? context.paths.summonHome
        refs["folder"] = folder.path
        if task.directory == nil { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        let brief = SessionBrief(mode: .scheduled(execution, limitMinutes: Int(runLimit / 60)), folder: folder.path,
                                 checkpointID: checkpoint.id, configCaptured: checkpoint.configCommit != nil,
                                 skillFiles: SkillCommands.skillFiles(agent: agent.id, settings: settings))
        let prompt = SessionBrief.scheduledPreamble(name: task.name) + task.prompt + brief.render()
        guard let argv = agent.headless(prompt: prompt, model: settings.model(for: agent.id), execution: execution) else {
            throw CLIError("\(agent.name) cannot run unattended yet.")
        }
        let logDir = context.paths.taskLogs.appendingPathComponent(task.id, isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let log = logDir.appendingPathComponent(UUID().uuidString + ".log")
        refs["file"] = log.path
        if checkpoint.configCommit == nil { context.warn("Checkpoint covers macctl-supported changes only; ~/.config was not captured.") }
        do {
            let status = try await runLogged(path, Array(argv.dropFirst()), in: folder, log: log, limit: runLimit)
            guard status == 0 else { throw CLIError("Agent exited with \(status). Log: \(log.path)") }
            ActivityCommands.record(LoggedEvent(kind: EventKind.taskDone, title: "Task done: \(task.name)",
                                               detail: lastLines(of: log, count: 3), refs: refs), context)
            await notify(title: "Task done", text: task.name, context)
            print("Done. Log: \(log.path)")
        } catch {
            ActivityCommands.record(LoggedEvent(kind: EventKind.taskFailed, title: "Task failed: \(task.name)",
                                               detail: String(describing: error), refs: refs), context)
            await notify(title: "Task failed", text: task.name, context)
            throw error
        }
    }

    /// Output is capped during execution; cancellation and timeout clean up the invocation's process group.
    static func runLogged(_ path: String, _ arguments: [String], in folder: URL, log: URL, limit: TimeInterval) async throws -> Int32 {
        var options = ProcessOptions()
        options.timeout = limit
        options.directory = folder
        options.logFile = log
        options.terminateDescendantsOnExit = true
        return try await ProcessExecutor.run(path, arguments, options: options).status
    }

    static func lastLines(of file: URL, count: Int) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").suffix(count).joined(separator: "\n")
        return lines.isEmpty ? nil : lines
    }

    /// Summon.app announces task results from the event log (with Show Log and Ask Agent). Only when it is not
    /// running does the CLI post a plain banner: a fixed script, the texts as argv.
    static func notify(title: String, text: String, _ context: Context) async {
        guard !AppHealthStore(paths: context.paths).appIsRunning() else { return }
        _ = try? await context.runner("/usr/bin/osascript", [
            "-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run",
            "Summon · " + title, text,
        ])
    }
}
