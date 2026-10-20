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
        let model = try AgentSettingsStore(paths: context.paths).loadValidated().model(for: agent.id)
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
        var options = ProcessOptions()
        options.timeout = limit
        options.includeStandardError = includeErrors
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = context.tools.searchPath.joined(separator: ":")
        environment["NO_COLOR"] = "1"
        options.environment = environment
        do {
            let result = try ProcessExecutor.runSync(path, arguments, options: options)
            return (result.status == 0 && !result.truncated, result.truncated ? "Probe output exceeded its limit" : result.output)
        } catch {
            return (false, String(describing: error))
        }
    }
}
