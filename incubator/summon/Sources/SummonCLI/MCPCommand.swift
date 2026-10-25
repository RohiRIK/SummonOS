import Foundation
import SummonCore

enum MCPCommand {
    /// `summon mcp`: an MCP server on stdin/stdout until stdin closes. Nothing else may write to stdout.
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        guard args.isEmpty else { throw CLIError("Usage: summon mcp") }
        let server = SummonMCP.server(SummonMCP.Environment(
            paths: context.paths, runner: context.runner, tools: context.tools,
            macctlPath: context.macctl, gitPath: context.git, version: SummonVersion.current))
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let reply = await server.handle(line: line) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
    }
}
