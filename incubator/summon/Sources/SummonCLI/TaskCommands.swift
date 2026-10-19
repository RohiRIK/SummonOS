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
        case "add": try add(&args, context)
        case nil, "list": try list(&args, context)
        case "remove": try remove(&args, context)
        case "run":
            guard let id = args.next() else { throw CLIError("Usage: summon task run <id>") }
            try await runTask(id, context)
        default:
            throw CLIError("Usage: summon task new [what you want] | summon task add <prompt> (--at HH:MM [--weekdays] | --every <n>h) [--agent <id>] [--name <name>] | list [--json] | remove <id> | run <id>")
        }
    }

    // MARK: add / list / remove

    static func add(_ args: inout Arguments, _ context: Context) throws {
        let weekdays = args.flag("--weekdays")
        let at = args.option("--at")
        let every = args.option("--every")
        let agentName = args.option("--agent")
        let name = args.option("--name")
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
        let store = TaskStore(paths: context.paths)
        let title = name ?? String(prompt.prefix(40))
        let task = RecurringTask(id: store.newID(for: title), name: title, prompt: prompt,
                                 agent: agentName.flatMap { AgentRegistry.find($0)?.id }, schedule: schedule)
        try store.save(store.load() + [task])
        try install(task, context)
        print("Added \(task.id): \(task.schedule.summary), \(task.agent ?? "default agent")")
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
        let rows = TaskStore(paths: context.paths).load().map { task -> TaskRow in
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

    static func remove(_ args: inout Arguments, _ context: Context) throws {
        guard let id = args.next() else { throw CLIError("Usage: summon task remove <id>") }
        let store = TaskStore(paths: context.paths)
        let tasks = store.load()
        guard tasks.contains(where: { $0.id == id }) else { throw CLIError("No task \(id)") }
        unschedule(id, context)
        try store.save(tasks.filter { $0.id != id })
        print("Removed \(id)")
    }

    // MARK: launchd

    static func install(_ task: RecurringTask, _ context: Context) throws {
        let logDir = context.paths.taskLogs.appendingPathComponent(task.id, isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let summon = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let file = TaskPlist.file(task.id, home: context.paths.home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TaskPlist.data(for: task, summon: summon, path: path, logDir: logDir.path).write(to: file, options: .atomic)
        unschedule(task.id, context, keepFile: true)
        _ = try Shell.runSync("/bin/launchctl", ["bootstrap", "gui/\(getuid())", file.path])
    }

    /// Unloading a job that is not loaded fails harmlessly.
    static func unschedule(_ id: String, _ context: Context, keepFile: Bool = false) {
        _ = try? Shell.runSync("/bin/launchctl", ["bootout", "gui/\(getuid())/\(TaskPlist.label(id))"])
        if !keepFile { try? FileManager.default.removeItem(at: TaskPlist.file(id, home: context.paths.home)) }
    }

    // MARK: run

    @MainActor
    static func runTask(_ id: String, _ context: Context) async throws {
        guard let task = TaskStore(paths: context.paths).load().first(where: { $0.id == id }) else { throw CLIError("No task \(id)") }
        guard let agent = task.agent.flatMap(AgentRegistry.find) ?? DefaultAgentStore(paths: context.paths).load() else {
            throw CLIError("No agent: set one with summon default agent <name>")
        }
        guard let path = context.tools.find(agent.command) else { throw CLIError("\(agent.name) is not installed: \(agent.installHint)") }
        let settings = AgentSettingsStore(paths: context.paths).load()
        let prompt = task.prompt + SkillCommands.promptFooter(agent: agent.id, settings: settings)
        guard let argv = agent.headless(prompt: prompt, model: settings.model(for: agent.id)) else {
            throw CLIError("\(agent.name) cannot run unattended yet.")
        }

        let service = CheckpointService(paths: context.paths, runner: context.runner, gitPath: context.git, macctlPath: context.macctl)
        let (checkpoint, _) = await service.create(label: "task: \(task.name)")

        let folder = context.paths.projects
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let logDir = context.paths.taskLogs.appendingPathComponent(task.id, isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let log = logDir.appendingPathComponent("\(stamp).log")
        let status = try await runLogged(path, Array(argv.dropFirst()), in: folder, log: log, limit: runLimit)

        let ok = status == 0
        ActivityCommands.record(LoggedEvent(
            kind: ok ? EventKind.taskDone : EventKind.taskFailed,
            title: ok ? "Task done: \(task.name)" : "Task failed: \(task.name) (exit \(status))",
            detail: lastLines(of: log, count: 3),
            refs: ["task": task.id, "agent": agent.id, "file": log.path, "checkpoint": checkpoint.id]
        ), context)
        notify(title: ok ? "Task done" : "Task failed", text: task.name)
        print(ok ? "Done. Log: \(log.path)" : "Failed (exit \(status)). Log: \(log.path)")
    }

    /// Runs with output to `log`, stops the process after `limit`, and returns its exit status.
    static func runLogged(_ path: String, _ arguments: [String], in folder: URL, log: URL, limit: TimeInterval) async throws -> Int32 {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                handle.write(Data("\nsummon: stopped after \(Int(limit / 60)) minutes\n".utf8))
                break
            }
            try await Task.sleep(for: .seconds(1))
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func lastLines(of file: URL, count: Int) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").suffix(count).joined(separator: "\n")
        return lines.isEmpty ? nil : lines
    }

    /// A banner without the app: a fixed script, the texts as argv.
    static func notify(title: String, text: String) {
        _ = try? Shell.runSync("/usr/bin/osascript", [
            "-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run",
            "Summon · " + title, text,
        ])
    }
}
