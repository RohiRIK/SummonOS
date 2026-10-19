import Foundation
import SummonCore

enum AgentCommands {
    /// `summon agent [--inline] [--no-checkpoint]` and `summon agent prompt [--inline] <prompt...>`.
    @MainActor
    static func agent(_ args: inout Arguments, _ context: Context) async throws {
        var prompt: String?
        if args.items.first == "prompt" {
            _ = args.next()
            // The prompt is taken verbatim; only a leading --inline is read as a flag.
            var inline = false
            if args.items.first == "--inline" {
                _ = args.next()
                inline = true
            }
            let text = args.items.joined(separator: " ")
            guard !text.isEmpty else { throw CLIError("Usage: summon agent prompt [--inline] <prompt...>") }
            prompt = text
            try await launch(prompt: prompt, inline: inline, checkpoint: true, context)
            return
        }
        let inline = args.flag("--inline")
        let skipCheckpoint = args.flag("--no-checkpoint")
        guard args.isEmpty else {
            throw CLIError("Unexpected argument: \(args.items.joined(separator: " "))\nTo pass a prompt: summon agent prompt \"...\"")
        }
        try await launch(prompt: nil, inline: inline, checkpoint: !skipCheckpoint, context)
    }

    /// Shared by `agent`, `agent prompt` and `crash diagnose`.
    @MainActor
    static func launch(prompt: String?, inline: Bool, checkpoint: Bool, _ context: Context) async throws {
        guard let agent = DefaultAgentStore(paths: context.paths).load() else {
            throw CLIError("No default agent yet. Choose one with: summon default agent <name>\nKnown: " + AgentRegistry.all.map(\.id).joined(separator: ", "))
        }
        guard let agentPath = context.tools.find(agent.command) else {
            throw CLIError("\(agent.name) is not installed. Install it with: \(agent.installHint)", code: .missingDependency)
        }

        var checkpointID: String?
        if checkpoint {
            let service = CheckpointService(paths: context.paths, runner: context.runner, gitPath: context.git, macctlPath: context.macctl)
            let (taken, problems) = await service.create(label: prompt.map { "agent: " + String($0.prefix(60)) } ?? "agent session")
            checkpointID = taken.id
            for problem in problems {
                context.warn("checkpoint: \(problem)")
            }
        }

        let fileManager = FileManager.default
        do {
            try ProjectsFolder.ensure(context.paths)
        } catch {
            context.warn("summon: could not create \(context.paths.projects.path): \(error)")
        }
        let directory = AgentLauncher.workingDirectory(
            current: fileManager.currentDirectoryPath,
            home: context.paths.home.path,
            projects: context.paths.projects.path
        )

        var refs = ["agent": agent.id, "folder": directory]
        refs["checkpoint"] = checkpointID
        ActivityCommands.record(LoggedEvent(
            kind: EventKind.agentLaunch,
            title: "Started \(agent.name)",
            detail: prompt.map { String($0.prefix(200)) },
            refs: refs
        ), context)

        // argv[0] stays the command name; the absolute path is what actually runs, so a GUI PATH cannot miss it.
        let settings = AgentSettingsStore(paths: context.paths).load()
        let argv = agent.argv(prompt: prompt.map { $0 + SkillCommands.promptFooter(agent: agent.id, settings: settings) },
                              model: settings.model(for: agent.id))
        if inline {
            _ = fileManager.changeCurrentDirectoryPath(directory)
            execReplacing(agentPath, argv)
        }
        let terminal = AgentLauncher.preferredTerminal(saved: DefaultTerminalStore(paths: context.paths).load(), installed: TerminalApp.installed)
        // Terminal.app's `do script` already runs the user's shell; Ghostty and kitty need it explicitly.
        let command = [agentPath] + argv.dropFirst()
        let agentArgv = terminal == .terminal ? command : AgentLauncher.inLoginShell(command, shell: ProcessInfo.processInfo.environment["SHELL"])
        let plan = AgentLauncher.terminalPlan(agentArgv: agentArgv, directory: directory, terminal: terminal)
        _ = try await context.runner(plan.executable, plan.arguments)
    }

    /// Replaces this process with the agent, so it owns the terminal. Returns only on failure.
    static func execReplacing(_ path: String, _ argv: [String]) -> Never {
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)
        execv(path, cArgs)
        perror("summon: execv")
        exit(ExitCode.error.rawValue)
    }

    /// `summon default agent [name]`. Silent when unset, like Omarchy: nothing is picked for you.
    static func defaultAgent(_ args: inout Arguments, _ context: Context) throws {
        let store = DefaultAgentStore(paths: context.paths)
        guard let name = args.next() else {
            if let agent = store.load() { print(agent.id) }
            return
        }
        guard let agent = AgentRegistry.find(name) else {
            throw CLIError("Unknown agent: \(name)\nKnown: " + AgentRegistry.all.map(\.id).joined(separator: ", "))
        }
        try store.save(agent)
        if context.tools.find(agent.command) == nil {
            print("Default agent is now \(agent.name). It is not installed yet; install it with: \(agent.installHint)")
        } else {
            print("Default agent is now \(agent.name).")
        }
    }

    /// `summon default terminal [name]`. Without a name, prints the terminal agents will open in.
    static func defaultTerminal(_ args: inout Arguments, _ context: Context) throws {
        let store = DefaultTerminalStore(paths: context.paths)
        guard let name = args.next() else {
            print(AgentLauncher.preferredTerminal(saved: store.load(), installed: TerminalApp.installed).rawValue)
            return
        }
        guard let terminal = TerminalApp(rawValue: name.lowercased()) else {
            throw CLIError("Unknown terminal: \(name)\nKnown: " + TerminalApp.allCases.map(\.rawValue).joined(separator: ", "))
        }
        try store.save(terminal)
        print(terminal.isInstalled
            ? "Agents now open in \(terminal.name)."
            : "Saved \(terminal.name), but it is not installed; agents open in \(AgentLauncher.preferredTerminal(saved: terminal, installed: TerminalApp.installed).name) until it is.")
    }

    struct AgentRow: Encodable {
        let id: String
        let name: String
        let installed: Bool
        let path: String?
        let isDefault: Bool
        let installHint: String
        let model: String?
        let skills: [String]
    }

    /// `summon agents defaults [--skills a,b | --all-skills]`: the All Agents skills every agent follows unless it
    /// has its own list. Saves and relinks at once.
    static func defaults(_ args: inout Arguments, _ context: Context) throws {
        let store = AgentSettingsStore(paths: context.paths)
        var settings = store.load()
        let shipped = SkillLinker.skillNames(in: SkillCommands.source)
        if args.flag("--all-skills") { settings.defaultSkills = nil }
        if let list = args.option("--skills") {
            let names = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let unknown = names.filter { !shipped.contains($0) }
            guard unknown.isEmpty else { throw CLIError("Unknown skill: \(unknown.joined(separator: ", "))\nShipped: \(shipped.joined(separator: ", "))") }
            settings.defaultSkills = names.sorted()
        }
        try store.save(settings)
        _ = try SkillLinker(home: context.paths.home).link(from: SkillCommands.source, settings: settings)
        print("All agents: skills \(settings.defaultSkills(shipped: shipped).joined(separator: ", "))")
    }

    /// `summon agents set <agent> [--model <m> | --default-model] [--skills a,b | --all-skills]`.
    static func set(_ args: inout Arguments, _ context: Context) throws {
        guard let name = args.next(), let agent = AgentRegistry.find(name) else {
            throw CLIError("Usage: summon agents set <agent> [--model <model> | --default-model] [--skills a,b | --all-skills]")
        }
        let store = AgentSettingsStore(paths: context.paths)
        var settings = store.load()
        let shipped = SkillLinker.skillNames(in: SkillCommands.source)
        if args.flag("--default-model") { settings.setModel(nil, for: agent.id) }
        if let model = args.option("--model") {
            guard agent.modelFlag != nil else { throw CLIError("\(agent.name) has no model option; set its model in its own config.") }
            settings.setModel(model, for: agent.id)
        }
        if args.flag("--all-skills") { settings.setSkills(nil, for: agent.id) }
        if let list = args.option("--skills") {
            let names = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let unknown = names.filter { !shipped.contains($0) }
            guard unknown.isEmpty else { throw CLIError("Unknown skill: \(unknown.joined(separator: ", "))\nShipped: \(shipped.joined(separator: ", "))") }
            settings.setSkills(names, for: agent.id)
        }
        try store.save(settings)
        _ = try SkillLinker(home: context.paths.home).link(from: SkillCommands.source, settings: settings)
        let model = settings.model(for: agent.id) ?? "its default"
        print("\(agent.name): model \(model); skills \(settings.skills(for: agent.id, shipped: shipped).joined(separator: ", "))")
    }

    static func list(_ args: inout Arguments, _ context: Context) throws {
        let json = args.flag("--json")
        let current = DefaultAgentStore(paths: context.paths).load()?.id
        let settings = AgentSettingsStore(paths: context.paths).load()
        let shipped = SkillLinker.skillNames(in: SkillCommands.source)
        let rows = AgentRegistry.all.map { agent -> AgentRow in
            let path = context.tools.find(agent.command)
            return AgentRow(id: agent.id, name: agent.name, installed: path != nil, path: path,
                            isDefault: agent.id == current, installHint: agent.installHint,
                            model: settings.model(for: agent.id), skills: settings.skills(for: agent.id, shipped: shipped))
        }
        if json {
            try context.printJSON(rows)
            return
        }
        for row in rows {
            let mark = row.isDefault ? "*" : " "
            let state = row.installed ? "installed" : "not installed (\(row.installHint))"
            let model = row.model.map { " · model \($0)" } ?? ""
            print("\(mark) \(row.id.padding(toLength: 13, withPad: " ", startingAt: 0)) \(row.name): \(state)\(model) · skills \(row.skills.joined(separator: ","))")
        }
    }

    /// `summon checkpoint create [--dry-run] [label] | list [--json] | undo [id] [--dry-run]`.
    static func checkpoint(_ args: inout Arguments, _ context: Context) async throws {
        let service = CheckpointService(paths: context.paths, runner: context.runner, gitPath: context.git, macctlPath: context.macctl)
        switch args.next() {
        case "create":
            let dryRun = args.flag("--dry-run")
            let label = args.items.isEmpty ? "manual" : args.items.joined(separator: " ")
            if dryRun {
                for step in service.createSteps(label: label) {
                    print(([step.executable] + step.arguments).joined(separator: " "))
                }
                return
            }
            let (checkpoint, problems) = await service.create(label: label)
            for problem in problems { context.warn(problem) }
            let commit = checkpoint.configCommit ?? "none"
            let snapshot = checkpoint.macctlSnapshot ?? "none"
            print("Checkpoint \(checkpoint.id) \"\(checkpoint.label)\": config commit \(commit), macctl marker \(snapshot)")
        case "list":
            let all = service.list()
            if args.flag("--json") {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(all), as: UTF8.self))
                return
            }
            if all.isEmpty { print("No checkpoints yet. One is taken every time `summon agent` starts.") }
            for checkpoint in all.reversed() {
                let commit = checkpoint.configCommit.map { String($0.prefix(8)) } ?? "-"
                let snapshot = checkpoint.macctlSnapshot ?? "-"
                print("\(checkpoint.id)  \(checkpoint.label)  config:\(commit)  macctl:\(snapshot)")
            }
        case "undo":
            try await undo(&args, service, context)
        default:
            throw CLIError("Usage: summon checkpoint create [label] | list [--json] | undo [id]")
        }
    }

    /// `summon undo-session` is `summon checkpoint undo` of the latest checkpoint.
    static func undoSession(_ args: inout Arguments, _ context: Context) async throws {
        let service = CheckpointService(paths: context.paths, runner: context.runner, gitPath: context.git, macctlPath: context.macctl)
        try await undo(&args, service, context)
    }

    static func undo(_ args: inout Arguments, _ service: CheckpointService, _ context: Context) async throws {
        let dryRun = args.flag("--dry-run")
        let id = args.next()
        guard let checkpoint = service.find(id) else {
            if let id { throw CLIError("No checkpoint \(id). See: summon checkpoint list") }
            throw CLIError("No checkpoint yet. One is taken every time `summon agent` starts.")
        }
        let snapshots = try await service.macctlSnapshots(after: checkpoint)
        let steps = service.undoSteps(checkpoint, macctlSnapshots: snapshots)
        guard !steps.isEmpty else {
            throw CLIError("Checkpoint \(checkpoint.id) has nothing to restore (no ~/.config git repo and no macctl changes since).")
        }
        for step in steps {
            let line = ([step.executable] + step.arguments).joined(separator: " ")
            if dryRun {
                print(line)
            } else {
                _ = try await context.runner(step.executable, step.arguments)
                print("ran: \(line)")
            }
        }
        if !dryRun {
            ActivityCommands.record(LoggedEvent(
                kind: EventKind.sessionUndo,
                title: "Restored checkpoint \(checkpoint.label)",
                detail: snapshots.isEmpty ? nil : "Undid macctl snapshots " + snapshots.joined(separator: ", "),
                refs: ["checkpoint": checkpoint.id]
            ), context)
            print("Restored checkpoint \(checkpoint.id) \"\(checkpoint.label)\". Files created after it were left in place; see `git -C ~/.config status`.")
        }
    }
}
