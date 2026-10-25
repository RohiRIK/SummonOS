import Foundation
import SummonCore

enum ConnectCommands {
    static let usage = "Usage: summon connect [agent...] [--dry-run] [--json] | summon disconnect [agent...] [--dry-run] [--json]"

    /// `summon connect` / `summon disconnect`: every agent target by default, or the named ones.
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context, remove: Bool) async throws {
        let dryRun = args.flag("--dry-run")
        let json = args.flag("--json")
        var targets: [ConnectTarget] = []
        while let name = args.next() {
            guard !name.hasPrefix("-"), let target = ConnectTarget.find(name) else {
                throw CLIError("Unknown agent: \(name). Agents: \(ConnectTarget.all.map(\.id).joined(separator: ", "))\n\(usage)")
            }
            targets.append(target)
        }
        if targets.isEmpty { targets = ConnectTarget.all }
        let connector = AgentConnector(paths: context.paths, runner: context.runner, tools: context.tools, summonPath: summonPath(context))
        let results = remove
            ? await connector.disconnect(targets, dryRun: dryRun)
            : await connector.connect(targets, dryRun: dryRun)
        if json { return try context.printJSON(results) }
        for result in results {
            let status = dryRun && result.status == .connected ? "would-connect" : dryRun && result.status == .disconnected ? "would-disconnect" : result.status.rawValue
            print("\(result.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(status)  \(result.detail)")
            for file in result.files { print("    \(dryRun ? "would change" : "changed") \(file)") }
        }
        if !dryRun, results.contains(where: { !$0.files.isEmpty }) {
            print("Backups: \(context.paths.state.appendingPathComponent("backups/connect").path)")
        }
        if results.contains(where: { $0.status == .failed }) { throw CLIError("", code: .error) }
    }

    /// The path agents should start: `summon` on PATH when it is this binary's install, else this binary.
    static func summonPath(_ context: Context) -> String {
        context.tools.find("summon") ?? Bundle.main.executablePath ?? CommandLine.arguments[0]
    }
}
