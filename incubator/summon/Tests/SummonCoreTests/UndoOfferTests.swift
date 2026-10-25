import Foundation
import Testing
@testable import SummonCore

@Suite("Undo an agent session: MCP checkpoints and the panel's one undo row")
struct UndoOfferTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func checkpoint(_ id: String, minutesAgo: Double) -> Checkpoint {
        Checkpoint(id: id, label: "Codex via MCP", createdAt: now.addingTimeInterval(-minutesAgo * 60), configCommit: nil, macctlSnapshot: nil)
    }

    static func change(_ id: String, minutesAgo: Double, count: Int = 1, undoes: String? = nil) -> MacctlSnapshot {
        MacctlSnapshot(id: id, createdAt: now.addingTimeInterval(-minutesAgo * 60),
                       changes: (0..<count).map { SettingChange(id: "dock.s\($0)", from: "false", to: "true") }, undoes: undoes)
    }

    @Test func offersTheNewestSessionWithItsChangeCount() {
        let sources = ActivitySources(
            log: [LoggedEvent(kind: EventKind.sessionStart, title: "Codex session started (MCP)", refs: ["checkpoint": "b", "agent": "Codex"])],
            snapshots: [Self.change("s1", minutesAgo: 50), Self.change("s2", minutesAgo: 20, count: 2), Self.change("s3", minutesAgo: 10)],
            checkpoints: [Self.checkpoint("a", minutesAgo: 60), Self.checkpoint("b", minutesAgo: 30)])
        let offer = UndoOffer.latest(sources, now: Self.now)
        #expect(offer == UndoOffer(checkpoint: "b", agent: "Codex", changes: 3))
        #expect(offer?.title == "Undo Codex Session (3 changes)…")
    }

    @Test func nothingToOfferWhenOldUndoneOrUnchanged() {
        let old = ActivitySources(snapshots: [Self.change("s", minutesAgo: 700)], checkpoints: [Self.checkpoint("a", minutesAgo: 13 * 60)])
        #expect(UndoOffer.latest(old, now: Self.now) == nil)
        let unchanged = ActivitySources(snapshots: [Self.change("s", minutesAgo: 90)], checkpoints: [Self.checkpoint("a", minutesAgo: 30)])
        #expect(UndoOffer.latest(unchanged, now: Self.now) == nil)
        let undone = ActivitySources(log: [LoggedEvent(kind: EventKind.sessionUndo, title: "Restored", refs: ["checkpoint": "a"])],
                                     snapshots: [Self.change("s", minutesAgo: 10)], checkpoints: [Self.checkpoint("a", minutesAgo: 30)])
        #expect(UndoOffer.latest(undone, now: Self.now) == nil)
        // A change already rolled back by its own undo leaves nothing to offer.
        let rolledBack = ActivitySources(snapshots: [Self.change("s", minutesAgo: 10), Self.change("u", minutesAgo: 5, undoes: "s")],
                                         checkpoints: [Self.checkpoint("a", minutesAgo: 30)])
        #expect(UndoOffer.latest(rolledBack, now: Self.now) == nil)
    }

    @Test func summonLaunchedSessionsShowTheAgentsName() {
        let sources = ActivitySources(log: [LoggedEvent(kind: EventKind.agentLaunch, title: "Started Claude Code", refs: ["checkpoint": "a", "agent": "claude"])],
                                      snapshots: [Self.change("s", minutesAgo: 5)], checkpoints: [Self.checkpoint("a", minutesAgo: 30)])
        #expect(UndoOffer.latest(sources, now: Self.now)?.agent == "Claude Code")
    }

    @Test func mcpClientNamesBecomeAgentNames() {
        #expect(SummonMCP.agentName("claude-code") == "Claude Code")
        #expect(SummonMCP.agentName("codex-mcp-client") == "Codex")
        #expect(SummonMCP.agentName("cursor-vscode") == "Cursor")
        #expect(SummonMCP.agentName("pi") == "Pi")
        #expect(SummonMCP.agentName("Zed") == "Zed")
        #expect(SummonMCP.agentName(nil) == "An agent")
    }

    @Test func firstRealChangeTakesOneCheckpointAndLogsTheSession() async throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        let log = CallLog()
        let session = MCPSession()
        let server = SummonMCP.server(SummonMCP.Environment(
            paths: paths, runner: fakeRunner(log, responses: ["macctl": #"{"ok": true}"#]),
            tools: ToolLocator(searchPath: [], isExecutable: { _ in false }), macctlPath: "/opt/bin/macctl", gitPath: nil, version: "0.1.0"),
            session: session)
        _ = await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-mcp-client"}}}"#)
        let dry = MCPServerTests.tool("settings_set", #"{"id":"dock.autohide","value":true,"dry_run":true}"#)
        _ = await server.handle(line: dry)
        #expect(await session.taken == nil)
        let set = MCPServerTests.tool("settings_set", #"{"id":"dock.autohide","value":true}"#)
        let reply = try #require(await server.handle(line: set))
        #expect(reply.contains("summon checkpoint undo"))
        _ = await server.handle(line: set)
        let checkpoint = try #require(await session.taken)
        #expect(checkpoint.label == "Codex via MCP")
        await session.end(SummonMCP.Environment(paths: paths, runner: fakeRunner(log), tools: ToolLocator(searchPath: [], isExecutable: { _ in false }),
                                                macctlPath: nil, gitPath: nil, version: "0.1.0"))
        let events = EventLog(paths: paths).read()
        #expect(events.map(\.kind) == [EventKind.sessionStart, EventKind.sessionEnd])
        #expect(events.allSatisfy { $0.refs["checkpoint"] == checkpoint.id && $0.refs["agent"] == "Codex" })
        #expect(try CheckpointService(paths: paths, runner: fakeRunner(log), gitPath: nil, macctlPath: nil).listValidated().count == 1)
    }
}
