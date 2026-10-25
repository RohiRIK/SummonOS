import Foundation
import Testing
@testable import SummonCore

@Suite("summon mcp: the MCP server every agent can use")
struct MCPServerTests {
    static func server(_ log: CallLog, responses: [String: String?] = ["macctl": #"{"ok": true, "result": []}"#],
                       macctl: String? = "/opt/bin/macctl") throws -> MCPServer {
        SummonMCP.server(SummonMCP.Environment(
            paths: SummonPaths(home: try makeTempHome()), runner: fakeRunner(log, responses: responses),
            tools: ToolLocator(searchPath: [], isExecutable: { _ in false }), macctlPath: macctl, gitPath: nil, version: "0.1.0"))
    }

    static func call(_ server: MCPServer, _ line: String) async throws -> JSONValue {
        let reply = try #require(await server.handle(line: line))
        #expect(!reply.contains("\n"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(reply.utf8))
    }

    static func tool(_ name: String, _ arguments: String) -> String {
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
    }

    @Test func initializeAgreesOnAVersionAndNotificationsGetNoReply() async throws {
        let server = try Self.server(CallLog())
        let reply = try await Self.call(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        #expect(reply["id"] == 1)
        #expect(reply["result"]?["protocolVersion"] == "2025-03-26")
        #expect(reply["result"]?["serverInfo"]?["name"] == "summon")
        #expect(reply["result"]?["capabilities"]?["tools"] != nil)
        let future = try await Self.call(server, #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        #expect(future["id"] == "a")
        #expect(future["result"]?["protocolVersion"]?.string == MCPServer.protocolVersions[0])
        #expect(await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func badMessagesGetJSONRPCErrors() async throws {
        let server = try Self.server(CallLog())
        #expect(try await Self.call(server, "not json")["error"]?["code"] == -32700)
        #expect(try await Self.call(server, #"{"jsonrpc":"2.0","id":2}"#)["error"]?["code"] == -32600)
        #expect(try await Self.call(server, #"{"jsonrpc":"2.0","id":3,"method":"nope"}"#)["error"]?["code"] == -32601)
        #expect(try await Self.call(server, Self.tool("nope", "{}"))["error"]?["code"] == -32602)
        #expect(try await Self.call(server, #"{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"mac://x"}}"#)["error"]?["code"] == -32002)
    }

    @Test func toolsAreFewDescribedAndMarkWhatOnlyReads() async throws {
        let reply = try await Self.call(try Self.server(CallLog()), #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let tools = try #require(reply["result"]?["tools"]?.array)
        // Agents choose worse with many tools; keep this list short.
        #expect(tools.count <= 15)
        #expect(tools.allSatisfy { $0["inputSchema"]?["type"] == "object" && $0["description"]?.string?.isEmpty == false })
        let readOnly = Dictionary(uniqueKeysWithValues: tools.compactMap { tool in
            tool["name"]?.string.map { ($0, tool["annotations"]?["readOnlyHint"]?.bool ?? false) }
        })
        #expect(readOnly["mac_context"] == true)
        #expect(readOnly["settings_get"] == true)
        #expect(readOnly["settings_set"] == false)
        #expect(readOnly["settings_undo"] == false)
    }

    @Test func settingsSetPassesFlagsBeforeTheIdAndValue() async throws {
        let log = CallLog()
        let server = try Self.server(log)
        let reply = try await Self.call(server, Self.tool("settings_set", #"{"id":"dock.tilesize","value":48,"dry_run":true,"confirm":true}"#))
        #expect(reply["result"]?["isError"] == false)
        #expect(reply["result"]?["structuredContent"]?["ok"] == .bool(true))
        _ = try await Self.call(server, Self.tool("settings_get", #"{"ids":["dock.autohide","finder.showhidden"]}"#))
        _ = try await Self.call(server, Self.tool("settings_undo", "{}"))
        #expect(await log.calls == [
            ["/opt/bin/macctl", "set", "--dry-run", "--yes", "--json", "--", "dock.tilesize", "48"],
            ["/opt/bin/macctl", "get", "--json", "--", "dock.autohide", "finder.showhidden"],
            ["/opt/bin/macctl", "undo", "--json"],
        ])
    }

    @Test func optionLookingIdsNeverReachMacctl() async throws {
        let log = CallLog()
        let server = try Self.server(log)
        for arguments in [#"{"ids":["--force"]}"#, #"{"ids":[]}"#, #"{"ids":["dock.autohide","-x"]}"#] {
            #expect(try await Self.call(server, Self.tool("settings_get", arguments))["result"]?["isError"] == true)
        }
        #expect(try await Self.call(server, Self.tool("settings_set", #"{"id":"-rf","value":"x"}"#))["result"]?["isError"] == true)
        #expect(try await Self.call(server, Self.tool("settings_set", #"{"id":"dock.autohide","value":[1]}"#))["result"]?["isError"] == true)
        #expect(try await Self.call(server, Self.tool("settings_undo", #"{"id":"--force"}"#))["result"]?["isError"] == true)
        #expect(await log.calls.isEmpty)
    }

    @Test func confirmationAndMissingMacctlTellTheAgentWhatToDo() async throws {
        let refused = try Self.server(CallLog(), responses: ["macctl": nil])
        let failed = try await Self.call(refused, Self.tool("settings_get", #"{"ids":["dock.autohide"]}"#))
        #expect(failed["result"]?["isError"] == true)
        let missing = try Self.server(CallLog(), macctl: nil)
        let text = try await Self.call(missing, Self.tool("settings_list", "{}"))["result"]?["content"]?.array?.first?["text"]?.string
        #expect(text?.contains("macctl is not installed") == true)
        let confirm = SummonMCP.output(#"{"ok": false}"#, isError: true)
        #expect(confirm.structured?["ok"] == .bool(false))
    }

    @Test func macContextRejectsUnknownSections() async throws {
        let server = try Self.server(CallLog())
        let reply = try await Self.call(server, Self.tool("mac_context", #"{"sections":["powr"]}"#))
        #expect(reply["result"]?["isError"] == true)
    }

    @Test func jsonValueRoundTripsIntegersAsIntegers() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":1,"b":1.5,"c":[true,null,"x"]}"#.utf8))
        #expect(value["a"] == 1)
        #expect(value["b"] == .double(1.5))
        #expect(MCPServer.encode(value) == #"{"a":1,"b":1.5,"c":[true,null,"x"]}"#)
    }
}
