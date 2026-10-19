import Foundation
import SummonCore

/// `summon agents status <agent> [--json]` and `summon agents login <agent>`.
enum AgentProbeCommands {
    static func status(_ args: inout Arguments, _ context: Context) throws {
        let json = args.flag("--json")
        guard let name = args.next(), let agent = AgentRegistry.find(name) else {
            throw CLIError("Usage: summon agents status <agent> [--json]")
        }
        guard let path = context.tools.find(agent.command) else {
            throw CLIError("\(agent.name) is not installed: \(agent.installHint)")
        }
        let model = AgentSettingsStore(paths: context.paths).load().model(for: agent.id)
        var login = AgentLogin(loggedIn: nil)
        var models = AgentProbe.models(agent, output: "")
        if let argv = AgentProbe.modelList(agent) {
            let (ok, output) = capture(path, Array(argv.dropFirst()), context)
            models = AgentProbe.models(agent, output: output)
            if AgentProbe.loginCheck(agent, model: model, piDefaultProvider: AgentProbe.piDefaultProvider(home: context.paths.home)) == nil { login = AgentProbe.login(agent, output: output, ok: ok) }
        }
        if let argv = AgentProbe.loginCheck(agent, model: model, piDefaultProvider: AgentProbe.piDefaultProvider(home: context.paths.home)) {
            // Codex prints its login state on stderr.
            let (ok, output) = capture(path, Array(argv.dropFirst()), context, includeErrors: true)
            login = AgentProbe.login(agent, output: output, ok: ok)
        }
        let status = AgentStatus(login: login, models: models)
        if json {
            try context.printJSON(status)
            return
        }
        let state = login.loggedIn.map { $0 ? "logged in" : "not logged in" } ?? "login unknown"
        print("\(agent.name): \(state)\(login.detail.map { " (\($0))" } ?? "") · \(models.count) models")
    }

    /// Opens the agent's own login in a terminal window.
    static func login(_ args: inout Arguments, _ context: Context) async throws {
        guard let name = args.next(), let agent = AgentRegistry.find(name) else {
            throw CLIError("Usage: summon agents login <agent>")
        }
        guard let path = context.tools.find(agent.command) else {
            throw CLIError("\(agent.name) is not installed: \(agent.installHint)")
        }
        let command = [path] + AgentProbe.loginAction(agent).dropFirst()
        let terminal = AgentLauncher.preferredTerminal(saved: DefaultTerminalStore(paths: context.paths).load(), installed: TerminalApp.installed)
        let argv = terminal == .terminal ? command : AgentLauncher.inLoginShell(command, shell: ProcessInfo.processInfo.environment["SHELL"])
        let plan = AgentLauncher.terminalPlan(agentArgv: argv, directory: context.paths.home.path, terminal: terminal)
        _ = try await context.runner(plan.executable, plan.arguments)
    }

    /// stdout (and stderr when asked) of a probe, at most 30 s. PATH is Summon's search path, so `#!/usr/bin/env node` CLIs find node
    /// even when Summon runs from the app (a GUI app has a bare PATH). stderr is dropped: shells and CLIs print noise.
    static func capture(_ path: String, _ arguments: [String], _ context: Context, includeErrors: Bool = false,
                        limit: TimeInterval = 30) -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = context.tools.searchPath.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let pipe = Pipe()
        let buffer = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { buffer.append(chunk) }
        }
        process.standardOutput = pipe
        process.standardError = includeErrors ? pipe : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (false, "") }
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.05)
        pipe.fileHandleForReading.readabilityHandler = nil
        return (process.terminationStatus == 0, String(decoding: buffer.data, as: UTF8.self))
    }
}
