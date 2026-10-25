import Foundation
import SummonCore

/// `summon agents install` and `summon agents update`: install a coding agent the Summon way (bun for npm agents,
/// else the vendor script) and update each the way it was installed.
enum AgentInstallCommands {
    /// `summon agents install <agent> [--yes]`.
    static func install(_ args: inout Arguments, _ context: Context) throws {
        let yes = args.flag("--yes")
        guard let name = args.next(), let agent = AgentRegistry.find(name) else {
            throw CLIError("Usage: summon agents install <agent> [--yes]\nKnown: " + AgentRegistry.all.map(\.id).joined(separator: ", "))
        }
        if let path = context.tools.find(agent.command) {
            print("\(agent.name) is already installed at \(path). To update it: summon agents update \(agent.id)")
            return
        }
        let updates = AgentUpdates(paths: context.paths, runner: context.runner, tools: context.tools)
        let step = try plan { try updates.installStep(for: agent) }
        try run(step, yes: yes, context)
        relinkSkills(context)
        print("Installed \(agent.name).")
    }

    /// `summon agents update [<agent>|--all] [--check] [--refresh] [--yes] [--json]`.
    static func update(_ args: inout Arguments, _ context: Context) async throws {
        let check = args.flag("--check"), refresh = args.flag("--refresh"), all = args.flag("--all")
        let yes = args.flag("--yes"), json = args.flag("--json")
        let updates = AgentUpdates(paths: context.paths, runner: context.runner, tools: context.tools)
        let name = args.next()
        let usage = "Usage: summon agents update [<agent>|--all] [--check] [--refresh] [--yes] [--json]"
        guard args.isEmpty else { throw CLIError(usage) }

        if check {
            let report = await updates.check(refresh: refresh)
            if json { return try context.printJSON(report) }
            printReport(report)
            return
        }

        var targets: [Agent]
        if let name {
            guard let agent = AgentRegistry.find(name) else { throw CLIError("Unknown agent: \(name)\n" + usage) }
            targets = [agent]
        } else if all {
            // Outdated per the check, plus vendor installs with a verified updater (they check for themselves).
            let report = await updates.check(refresh: refresh)
            let outdated = Set(report.agents.filter(\.updateAvailable).map(\.id))
            targets = updates.installed().filter { item in
                outdated.contains(item.agent.id) || (item.detected.method == .vendor && item.agent.install.selfUpdate != nil)
            }.map(\.agent)
            if targets.isEmpty {
                print("Every installed agent is up to date.")
                return
            }
        } else {
            throw CLIError(usage)
        }

        struct Result: Encodable { let id: String; let command: String; let ok: Bool; let error: String? }
        var results: [Result] = []
        for agent in targets {
            do {
                let step = try plan { try updates.updateStep(for: agent) }
                try run(step, yes: yes, context)
                updates.markUpdated(agent.id)
                results.append(Result(id: agent.id, command: step.display, ok: true, error: nil))
            } catch let error as CLIError {
                if targets.count == 1 { throw error }
                context.warn("\(agent.name): \(error.message)")
                results.append(Result(id: agent.id, command: "", ok: false, error: error.message))
            }
        }
        relinkSkills(context)
        if json { try context.printJSON(results) }
        if results.contains(where: { !$0.ok }) { throw CLIError("Some agents were not updated.") }
    }

    private static func plan(_ make: () throws -> InstallStep) throws -> InstallStep {
        do { return try make() } catch let error as AgentInstallError {
            throw CLIError(error.description, code: .missingDependency)
        }
    }

    /// Runs with the terminal attached so installers show progress (and can ask for input). No timeout: installs
    /// can take minutes. A vendor script needs a yes: `--yes`, or a typed y on a terminal.
    private static func run(_ step: InstallStep, yes: Bool, _ context: Context) throws {
        if step.needsConfirmation && !yes {
            guard isatty(STDIN_FILENO) == 1 else {
                throw CLIError("This runs the vendor's install script: \(step.display)\nRerun with --yes to allow it.")
            }
            FileHandle.standardError.write(Data("Run the vendor's install script?\n  \(step.display)\n[y/N] ".utf8))
            guard readLine()?.lowercased().hasPrefix("y") == true else { throw CLIError("Cancelled.") }
        }
        context.warn("$ " + step.display)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: step.executable)
        process.arguments = step.arguments
        do { try process.run() } catch { throw CLIError("Could not run \(step.display): \(error)") }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError("\(step.display) exited with \(process.terminationStatus).")
        }
    }

    /// Skills go only to installed agents, so a new or moved agent gets them right away.
    private static func relinkSkills(_ context: Context) {
        var link = Arguments(["link", "--quiet"])
        do { try SkillCommands.run(&link, context) } catch { context.warn("summon: skills link failed: \(error)") }
    }

    private static func printReport(_ report: AgentUpdateReport) {
        if report.agents.isEmpty { print("No agents are installed. Install one with: summon agents install <agent>") }
        for row in report.agents {
            let method = row.brewName.map { "\(row.method.rawValue) \($0)" } ?? row.method.rawValue
            let status = row.updateAvailable ? "update available"
                : row.current == nil ? "version unknown (\(row.id) --version failed)"
                : row.latest == nil ? "latest unknown" : "up to date"
            print("\(row.id.padding(toLength: 13, withPad: " ", startingAt: 0)) \(method.padding(toLength: 22, withPad: " ", startingAt: 0)) "
                + "\((row.current ?? "?").padding(toLength: 12, withPad: " ", startingAt: 0)) \((row.latest ?? "-").padding(toLength: 12, withPad: " ", startingAt: 0)) \(status)")
        }
        let formatter = ISO8601DateFormatter()
        print("\(report.updateCount) update(s) available · checked \(formatter.string(from: report.checkedAt))")
    }
}
