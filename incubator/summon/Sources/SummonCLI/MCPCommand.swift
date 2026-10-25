import Foundation
import SummonCore

enum MCPCommand {
    /// `summon mcp`: an MCP server on stdin/stdout until stdin closes. Nothing else may write to stdout.
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        guard args.isEmpty else { throw CLIError("Usage: summon mcp") }
        let environment = SummonMCP.Environment(
            paths: context.paths, runner: context.runner, tools: context.tools,
            macctlPath: context.macctl, gitPath: context.git, version: SummonVersion.current)
        let session = MCPSession()
        let server = SummonMCP.server(environment, session: session)
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let reply = await server.handle(line: line) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
        await session.end(environment)
    }
}
