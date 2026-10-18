import Foundation
import Testing
@testable import SummonCore

@Suite("Per-agent settings: model and skills")
struct AgentSettingsTests {
    @Test func modelGoesRightAfterTheCommand() throws {
        let claude = try #require(AgentRegistry.find("claude"))
        #expect(claude.argv(prompt: "fix it", model: "opus")
            == ["claude", "--model", "opus", "--dangerously-skip-permissions", "--", "fix it"])
        #expect(claude.argv(prompt: nil, model: " ") == claude.interactive)
        let opencode = try #require(AgentRegistry.find("opencode"))
        // OpenCode's TUI has no model flag; its config chooses the model.
        #expect(opencode.argv(prompt: nil, model: "anthropic/claude") == opencode.interactive)
    }

    @Test func installedAgentsHaveTheirOwnSkillFolder() {
        let folders = Dictionary(uniqueKeysWithValues: AgentRegistry.all.compactMap { a in a.skillFolder.map { (a.id, $0) } })
        #expect(folders["claude"] == ".claude/skills")
        #expect(folders["codex"] == ".codex/skills")
        #expect(folders["opencode"] == ".config/opencode/skills")
        #expect(folders["agy"] == ".gemini/config/skills")
        #expect(folders["pi"] == ".pi/agent/skills")
    }

    @Test func settingsRoundTripAndDefaultToEverySkill() throws {
        let store = AgentSettingsStore(paths: SummonPaths(home: try makeTempHome()))
        var settings = store.load()
        #expect(settings.model(for: "claude") == nil)
        #expect(settings.skills(for: "claude", shipped: ["mac-app", "summon"]) == ["mac-app", "summon"])
        settings.setModel("opus", for: "claude")
        settings.setSkills(["summon"], for: "codex")
        try store.save(settings)
        let loaded = store.load()
        #expect(loaded.model(for: "claude") == "opus")
        #expect(loaded.skills(for: "codex", shipped: ["mac-app", "summon"]) == ["summon"])
        settings.setModel("", for: "claude")
        #expect(settings.model(for: "claude") == nil)
    }
}
