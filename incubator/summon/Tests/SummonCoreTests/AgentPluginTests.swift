import Foundation
import Testing
@testable import SummonCore

@Suite("Agent plugins: list, add, shared catalog")
struct AgentPluginTests {
    func agent(_ id: String) throws -> Agent { try #require(AgentRegistry.find(id)) }

    @Test func claudePluginList() throws {
        let out = """
            Installed plugins:

              ❯ caveman@caveman
                Version: 4.0.1
                Status: ✔ enabled
              ❯ dev-team@rohirikman
                Status: ✘ disabled
            """
        #expect(AgentPlugins.parse(try agent("claude"), output: out) == [
            InstalledPlugin(name: "caveman@caveman", version: "4.0.1", enabled: true),
            InstalledPlugin(name: "dev-team@rohirikman", version: nil, enabled: false),
        ])
        #expect(AgentPlugins.install(try agent("claude"), spec: "openltm@OpenLtm") == ["claude", "plugin", "install", "openltm@OpenLtm"])
    }

    @Test func antigravityAndPiLists() throws {
        let agy = "Installed plugins:\n- arckit (enabled, 4.0.1)\n    Source:     gemini-cli\n- notion-extension (disabled, 3.0.4)\n"
        #expect(AgentPlugins.parse(try agent("agy"), output: agy) == [
            InstalledPlugin(name: "arckit", version: "4.0.1", enabled: true),
            InstalledPlugin(name: "notion-extension", version: "3.0.4", enabled: false),
        ])
        let pi = "User packages:\n  npm:@rohirik/pi-ltm (filtered)\n    /u/a/.pi/agent/npm/node_modules/@rohirik/pi-ltm\n  npm:context-mode\n    /u/a/x\n"
        #expect(AgentPlugins.parse(try agent("pi"), output: pi).map(\.name) == ["npm:@rohirik/pi-ltm", "npm:context-mode"])
        #expect(AgentPlugins.install(try agent("pi"), spec: "npm:x") == ["pi", "install", "npm:x"])
    }

    @Test func opencodePluginsLiveInItsConfig() throws {
        let home = try makeTempHome()
        let config = home.appendingPathComponent(".config/opencode/opencode.json")
        try writeFile(#"{"$schema": "https://opencode.ai/config.json", "plugin": ["@rohirik/opencode-ltm@latest"]}"#, to: config)
        #expect(AgentPlugins.opencodePlugins(home: home).map(\.name) == ["@rohirik/opencode-ltm@latest"])
        try AgentPlugins.addOpencodePlugin("context-mode", home: home)
        try AgentPlugins.addOpencodePlugin("context-mode", home: home)
        #expect(AgentPlugins.opencodePlugins(home: home).map(\.name) == ["@rohirik/opencode-ltm@latest", "context-mode"])
        let saved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        #expect(saved["$schema"] as? String == "https://opencode.ai/config.json")
        #expect(FileManager.default.fileExists(atPath: config.path + ".summon-backup"))
    }

    @Test func catalogKnowsOpenLTMPerAgent() throws {
        let openltm = try #require(PluginCatalog.all.first { $0.id == "openltm" })
        #expect(openltm.builds["claude"] == "openltm@OpenLtm")
        #expect(openltm.builds["opencode"] == "@rohirik/opencode-ltm@latest")
        #expect(openltm.builds["pi"] == "npm:@rohirik/pi-ltm")
        #expect(openltm.isInstalled(for: "pi", in: [InstalledPlugin(name: "npm:@rohirik/pi-ltm", version: nil, enabled: true)]))
        #expect(!openltm.isInstalled(for: "claude", in: [InstalledPlugin(name: "caveman@caveman", version: nil, enabled: true)]))
        #expect(PluginCatalog.fixPrompt(openltm, agent: try agent("opencode")).contains("@rohirik/opencode-ltm@latest"))
    }
}
