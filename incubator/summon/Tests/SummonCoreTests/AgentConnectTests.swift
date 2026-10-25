import Foundation
import Testing
@testable import SummonCore

@Suite("summon connect: the MCP server and a This Mac note in every agent")
struct AgentConnectTests {
    static func connector(home: URL, installed: Set<String>, log: CallLog, responses: [String: String?] = [:]) -> AgentConnector {
        AgentConnector(paths: SummonPaths(home: home), runner: fakeRunner(log, responses: responses),
                       tools: ToolLocator(searchPath: ["/fake/bin"], isExecutable: { installed.contains(($0 as NSString).lastPathComponent) }),
                       summonPath: "/opt/summon/bin/summon")
    }

    static func target(_ id: String) throws -> ConnectTarget { try #require(ConnectTarget.find(id)) }

    @Test func targetsAreTheOwnersAgentsAndNotGemini() {
        #expect(ConnectTarget.all.map(\.id) == ["claude", "codex", "cursor", "opencode", "hermes", "openclaw", "agy", "pi"])
        #expect(ConnectTarget.find("gemini")?.id == "agy")
        #expect(ConnectTarget.find("cursor-agent")?.id == "cursor")
        #expect(AgentRegistry.find("hermes") != nil && AgentRegistry.find("openclaw") != nil)
    }

    @Test func cliAgentsUseTheirOwnMcpAddAndSkipWhenAlreadyThere() async throws {
        let home = try makeTempHome()
        let log = CallLog()
        // codex's `mcp get summon` succeeds (already connected); claude's CLI fails on get and add.
        let connector = Self.connector(home: home, installed: ["claude", "codex"], log: log, responses: ["claude": nil])
        let results = await connector.connect([try Self.target("claude"), try Self.target("codex"), try Self.target("hermes")], dryRun: false)
        #expect(results.map(\.status) == [.failed, .connected, .notInstalled])
        let calls = await log.calls
        #expect(calls.contains(["/fake/bin/claude", "mcp", "get", "summon"]))
        #expect(calls.contains(["/fake/bin/claude", "mcp", "add", "--scope", "user", "summon", "--", "/opt/summon/bin/summon", "mcp"]))
        #expect(calls.contains(["/fake/bin/codex", "mcp", "get", "summon"]))
        #expect(!calls.contains { $0.count > 2 && $0[0] == "/fake/bin/codex" && $0[2] == "add" })
        #expect(TextFile.read(home.appendingPathComponent(".codex/AGENTS.md"))?.contains("summon context") == true)
        // A failed server add leaves the instructions file alone.
        #expect(TextFile.read(home.appendingPathComponent(".claude/CLAUDE.md")) == nil)
    }

    @Test func jsonFilesKeepOtherKeysAndRefuseNonObjects() async throws {
        let home = try makeTempHome()
        let file = home.appendingPathComponent(".pi/agent/mcp.json")
        try writeFile(#"{"theme":"dark","mcpServers":{"other":{"command":"x"}}}"#, to: file)
        let connector = Self.connector(home: home, installed: [], log: CallLog())
        let pi = try Self.target("pi")
        #expect(await connector.connect([pi], dryRun: false).first?.status == .connected)
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(root["theme"] as? String == "dark")
        let servers = try #require(root["mcpServers"] as? [String: Any])
        #expect(servers["other"] != nil)
        let summon = try #require(servers["summon"] as? [String: Any])
        #expect(summon["command"] as? String == "/opt/summon/bin/summon")
        #expect(summon["args"] as? [String] == ["mcp"])
        #expect(await connector.connect([pi], dryRun: false).first?.status == .alreadyConnected)

        try writeFile("[1, 2]", to: file)
        #expect(await connector.connect([pi], dryRun: false).first?.status == .failed)
        #expect(TextFile.read(file) == "[1, 2]")
    }

    @Test func disconnectRemovesOnlySummonAndBackupsExist() async throws {
        let home = try makeTempHome()
        let notes = home.appendingPathComponent(".pi/agent/AGENTS.md")
        try writeFile("# Mine\n- keep me\n", to: notes)
        try writeFile(#"{"mcpServers":{"other":{"command":"x"}}}"#, to: home.appendingPathComponent(".pi/agent/mcp.json"))
        let connector = Self.connector(home: home, installed: ["pi"], log: CallLog())
        let pi = try Self.target("pi")
        _ = await connector.connect([pi], dryRun: false)
        #expect(TextFile.read(notes)?.contains(AgentConnector.blockStart) == true)
        let results = await connector.disconnect([pi], dryRun: false)
        #expect(results.first?.status == .disconnected)
        #expect(TextFile.read(notes) == "# Mine\n- keep me\n")
        let servers = try #require((try JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".pi/agent/mcp.json"))) as? [String: Any])?["mcpServers"] as? [String: Any])
        #expect(servers.keys.sorted() == ["other"])
        let backups = SummonPaths(home: home).state.appendingPathComponent("backups/connect")
        #expect(FileManager.default.enumerator(atPath: backups.path)?.allObjects.contains { ($0 as? String)?.hasSuffix("AGENTS.md") == true } == true)
    }

    @Test func dryRunWritesNothing() async throws {
        let home = try makeTempHome()
        let log = CallLog()
        let connector = Self.connector(home: home, installed: ["claude", "pi"], log: log, responses: ["claude": nil])
        let results = await connector.connect([try Self.target("pi")], dryRun: true)
        #expect(results.first?.status == .connected)
        #expect(results.first?.files == ["~/.pi/agent/mcp.json", "~/.pi/agent/AGENTS.md"])
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".pi").path))
        #expect(await log.calls.isEmpty)
    }

    @Test func blockIsReplacedInPlaceAndRemovedCleanly() {
        let block = AgentConnector.block
        let added = AgentConnector.replacingBlock(in: "# Mine\n", with: block)
        #expect(added == "# Mine\n\n" + block + "\n")
        #expect(AgentConnector.replacingBlock(in: added, with: block) == added)
        #expect(AgentConnector.replacingBlock(in: added, with: nil) == "# Mine\n")
        let middle = "top\n" + block + "\nbottom\n"
        #expect(AgentConnector.replacingBlock(in: middle, with: nil) == "top\nbottom\n")
        #expect(AgentConnector.replacingBlock(in: "", with: block) == block + "\n")
        #expect(AgentConnector.replacingBlock(in: block + "\n", with: nil) == "")
        #expect(AgentConnector.replacingBlock(in: "no block\n", with: nil) == "no block\n")
    }

    @Test func markersDetectAnAppWithoutItsCommand() throws {
        let home = try makeTempHome()
        let cursor = try Self.target("cursor")
        let without = AgentConnector(paths: SummonPaths(home: home), runner: fakeRunner(CallLog()),
                                     tools: ToolLocator(searchPath: [], isExecutable: { _ in false }), summonPath: "/s",
                                     fileExists: { _ in false })
        #expect(!without.isPresent(cursor))
        let withApp = AgentConnector(paths: SummonPaths(home: home), runner: fakeRunner(CallLog()),
                                     tools: ToolLocator(searchPath: [], isExecutable: { _ in false }), summonPath: "/s",
                                     fileExists: { $0 == "/Applications/Cursor.app" })
        #expect(withApp.isPresent(cursor))
    }

    @Test func startHooksKeepTheUsersHooksAndComeOffCleanly() async throws {
        let home = try makeTempHome()
        let settings = home.appendingPathComponent(".claude/settings.json")
        let mine = #"{"model":"opus","hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"echo mine"}]}]}}"#
        try writeFile(mine, to: settings)
        let cursorHooks = home.appendingPathComponent(".cursor/hooks.json")
        try writeFile(#"{"version":1,"hooks":{"sessionStart":[{"command":"./mine.sh"}]}}"#, to: cursorHooks)
        // claude's `mcp get` succeeds (already connected), so only the files change.
        let connector = Self.connector(home: home, installed: ["claude", "cursor-agent", "agy"], log: CallLog())
        let targets = [try Self.target("claude"), try Self.target("cursor"), try Self.target("agy")]
        let results = await connector.connect(targets, dryRun: false)
        #expect(results.allSatisfy { $0.status == .connected })

        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect(root["model"] as? String == "opus")
        let groups = try #require((root["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]])
        #expect(groups.count == 2)
        let command = try #require((groups.last?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        #expect(command == #""/opt/summon/bin/summon" context --hook claude"#)
        let ends = try #require((root["hooks"] as? [String: Any])?["SessionEnd"] as? [[String: Any]])
        #expect((ends.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String == #""/opt/summon/bin/summon" event hook end --agent claude"#)
        let cursor = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: cursorHooks)) as? [String: Any])
        #expect(((cursor["hooks"] as? [String: Any])?["sessionStart"] as? [Any])?.count == 2)
        let agy = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".gemini/config/hooks.json"))) as? [String: Any])
        #expect(agy["summon-context"] != nil)

        // A second connect adds no duplicate hook.
        _ = await connector.connect(targets, dryRun: false)
        let again = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect(((again["hooks"] as? [String: Any])?["SessionStart"] as? [Any])?.count == 2)

        _ = await connector.disconnect(targets, dryRun: false)
        let restored = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? NSDictionary)
        #expect(restored == (try JSONSerialization.jsonObject(with: Data(mine.utf8)) as? NSDictionary))
        let cursorAfter = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: cursorHooks)) as? [String: Any])
        #expect(((cursorAfter["hooks"] as? [String: Any])?["sessionStart"] as? [Any])?.count == 1)
    }
}
