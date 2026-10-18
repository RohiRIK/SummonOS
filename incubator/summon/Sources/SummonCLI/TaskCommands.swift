import Foundation
import SummonCore

/// `summon task add|list|run|log|enable|disable|remove`: prompts the agent runs on a schedule, headless,
/// behind a checkpoint, each through its own LaunchAgent.
enum TaskCommands {
    static let usage = """
        Usage: summon task add <name> (--every 30m|2h|1d | --at HH:MM [--days mon,wed|weekdays|weekends]) [--agent <id>] [--folder <path>] [--timeout 30m] -- <prompt...>
               summon task list [--json]
               summon task run <name>
               summon task log <name>
               summon task enable|disable|remove <name>
        """

    static func run(_ args: inout Arguments, _ context: Context) async throws {
        switch args.next() {
        case "add": try await add(&args, context)
        case "list": try list(&args, context)
        case "run": try await runNow(&args, context)
        case "log": try log(&args, context)
        case "enable": try await setEnabled(true, &args, context)
        case "disable": try await setEnabled(false, &args, context)
        case "remove": try await remove(&args, context)
        default: throw CLIError(usage)
        }
    }

    static func add(_ args: inout Arguments, _ context: Context) async throws {
        // Everything after `--` is the prompt, verbatim, so it may contain words that look like flags.
        var prompt = ""
        if let split = args.items.firstIndex(of: "--") {
            prompt = args.items[args.items.index(after: split)...].joined(separator: " ")
            args = Arguments(Array(args.items[..<split]))
        }
        let every = args.option("--every")
        let at = args.option("--at")
        let days = args.option("--days")
        let agentName = args.option("--agent")
        let folder = args.option("--folder")
        let timeoutText = args.option("--timeout")
        guard let name = args.next() else { throw CLIError(usage) }
        if prompt.isEmpty { prompt = args.items.joined(separator: " ") }
        guard AgentTask.isValidID(name) else {
            throw CLIError("Task names are kebab-case, start with a letter and have at most 40 characters: \(name)")
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CLIError("The task needs a prompt.\n" + usage) }

        let schedule: TaskSchedule
        switch (every, at) {
        case let (every?, nil):
            guard days == nil else { throw CLIError("--days goes with --at, not --every") }
            guard let parsed = TaskSchedule.parseEvery(every) else {
                throw CLIError("--every takes minutes, hours or days, at least \(TaskSchedule.minimumMinutes)m: 30m, 2h, 1d")
            }
            schedule = parsed
        case let (nil, at?):
            guard let parsed = TaskSchedule.parseAt(at, days: days) else {
                throw CLIError("--at takes HH:MM (24-hour); --days takes mon,tue,… or weekdays, weekends, daily")
            }
            schedule = parsed
        default:
            throw CLIError("Give exactly one of --every or --at.\n" + usage)
        }

        var agentID: String?
        if let agentName {
            guard let agent = AgentRegistry.find(agentName) else {
                throw CLIError("Unknown agent: \(agentName)\nKnown: " + AgentRegistry.all.map(\.id).joined(separator: ", "))
            }
            guard agent.headless != nil else { throw CLIError(noHeadless(agent)) }
            agentID = agent.id
        } else if let agent = DefaultAgentStore(paths: context.paths).load(), agent.headless == nil {
            context.warn("Note: the default agent, \(agent.name), cannot run tasks. " + supported)
        }

        var timeout = AgentTask.defaultTimeoutMinutes
        if let timeoutText {
            guard case let .every(minutes)? = TaskSchedule.parseEvery(timeoutText) else {
                throw CLIError("--timeout takes minutes or hours, at least \(TaskSchedule.minimumMinutes)m: 30m, 2h")
            }
            timeout = minutes
        }

        let store = TaskStore(paths: context.paths)
        var list = try store.load()
        let existing = list.find(name)
        let task = AgentTask(id: name, prompt: prompt, schedule: schedule, agent: agentID,
                             folder: folder.map { ($0 as NSString).expandingTildeInPath },
                             enabled: true, timeoutMinutes: timeout, created: existing?.created ?? Date())
        list.upsert(task)
        try store.save(list)
        try await sync(task, context)
        print("\(existing == nil ? "Added" : "Updated") task \(name): \(schedule.summary). Run it now with: summon task run \(name)")
    }

    struct TaskRow: Encodable {
        let id: String
        let prompt: String
        let schedule: String
        let enabled: Bool
        let agent: String?
        let folder: String?
        let timeoutMinutes: Int
        let lastRun: Date?
        let lastStatus: String?
        let lastSummary: String?
    }

    static func list(_ args: inout Arguments, _ context: Context) throws {
        let json = args.flag("--json")
        guard args.isEmpty else { throw CLIError("Usage: summon task list [--json]") }
        let tasks = try TaskStore(paths: context.paths).load().tasks
        let runs = EventLog(paths: context.paths).lastTaskRuns()
        let rows = tasks.map { task in
            TaskRow(id: task.id, prompt: task.prompt, schedule: task.schedule.summary, enabled: task.enabled,
                    agent: task.agent, folder: task.folder, timeoutMinutes: task.timeoutMinutes,
                    lastRun: runs[task.id]?.time, lastStatus: runs[task.id]?.refs["status"], lastSummary: runs[task.id]?.detail)
        }
        if json {
            try ActivityCommands.printJSON(rows)
            return
        }
        if rows.isEmpty {
            print("No tasks yet. Add one: summon task add morning-check --at 09:00 -- \"Summarize last night's crash reports\"")
            return
        }
        for row in rows {
            let state = row.enabled ? row.schedule : "off (\(row.schedule))"
            let last = row.lastRun.map { " · last run \($0.formatted(date: .abbreviated, time: .shortened)): \(row.lastStatus ?? "?")" } ?? " · never run"
            print("\(row.id)  \(state)\(last)")
            print("    \(row.prompt.prefix(100))")
        }
    }

    /// `summon task run <name> [--scheduled]`. `--scheduled` is how the LaunchAgent calls it: a task that was
    /// removed or turned off since cleans up its own job instead of running.
    static func runNow(_ args: inout Arguments, _ context: Context) async throws {
        let scheduled = args.flag("--scheduled")
        guard let name = args.next(), args.isEmpty else { throw CLIError("Usage: summon task run <name>") }
        let found = try TaskStore(paths: context.paths).load().find(name)
        guard let task = found, task.enabled || !scheduled else {
            if scheduled {
                await TaskLaunchAgent.remove(name, paths: context.paths, runner: context.runner, uid: getuid())
                return
            }
            throw CLIError("No task \(name). See: summon task list")
        }
        let runner = TaskRunner(paths: context.paths, runner: context.runner, execute: Shell.logged, tools: context.tools,
                                gitPath: context.git, macctlPath: context.macctl)
        let footer = SkillCommands.promptFooter(agent: task.agent ?? DefaultAgentStore(paths: context.paths).load()?.id ?? "",
                                                settings: AgentSettingsStore(paths: context.paths).load())
        if !scheduled { print("Running \(name)…") }
        let result = await runner.run(task, footer: footer)
        let log = result.log.map { "\nOutput: \($0.path)" } ?? ""
        switch result.status {
        case .ok:
            print("Task \(name) finished.\(log)")
        case .failed, .timeout, .skipped:
            throw CLIError("Task \(name) \(result.status.rawValue): \(result.summary)\(log)")
        }
    }

    static func log(_ args: inout Arguments, _ context: Context) throws {
        guard let name = args.next(), args.isEmpty else { throw CLIError("Usage: summon task log <name>") }
        let runner = TaskRunner(paths: context.paths, runner: context.runner, execute: Shell.logged, tools: context.tools,
                                gitPath: context.git, macctlPath: context.macctl)
        guard let file = runner.latestLog(name), let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw CLIError("Task \(name) has not run yet.")
        }
        print(file.path)
        print(text)
    }

    static func setEnabled(_ enabled: Bool, _ args: inout Arguments, _ context: Context) async throws {
        guard let name = args.next(), args.isEmpty else { throw CLIError("Usage: summon task \(enabled ? "enable" : "disable") <name>") }
        let store = TaskStore(paths: context.paths)
        var list = try store.load()
        guard var task = list.find(name) else { throw CLIError("No task \(name). See: summon task list") }
        task.enabled = enabled
        list.upsert(task)
        try store.save(list)
        try await sync(task, context)
        print(enabled ? "Task \(name) is on: \(task.schedule.summary)." : "Task \(name) is off.")
    }

    static func remove(_ args: inout Arguments, _ context: Context) async throws {
        guard let name = args.next(), args.isEmpty else { throw CLIError("Usage: summon task remove <name>") }
        let store = TaskStore(paths: context.paths)
        var list = try store.load()
        guard list.remove(name) != nil else { throw CLIError("No task \(name). See: summon task list") }
        try store.save(list)
        await TaskLaunchAgent.remove(name, paths: context.paths, runner: context.runner, uid: getuid())
        print("Removed task \(name). Its past output stays in \(context.paths.taskState.appendingPathComponent(name).path).")
    }

    static func sync(_ task: AgentTask, _ context: Context) async throws {
        let problems = try await TaskLaunchAgent.sync(task, summonPath: stableSummonPath(context), paths: context.paths,
                                                      runner: context.runner, uid: getuid())
        for problem in problems { context.warn(problem) }
    }

    /// `~/.local/bin/summon` (install.sh's link) survives app updates; otherwise this binary's real path.
    static func stableSummonPath(_ context: Context) -> String {
        let link = context.paths.home.appendingPathComponent(".local/bin/summon").path
        if FileManager.default.isExecutableFile(atPath: link) { return link }
        return (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    }

    static let supported = "Tasks run with " + AgentRegistry.all.filter { $0.headless != nil }.map(\.name).joined(separator: ", ") + "."

    static func noHeadless(_ agent: Agent) -> String {
        "\(agent.name) has no headless mode Summon can schedule. " + supported
    }
}
