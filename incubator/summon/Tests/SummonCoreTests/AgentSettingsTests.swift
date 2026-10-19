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

@Suite("All Agents defaults")
struct AgentDefaultsTests {
    let shipped = ["mac-app", "summon", "summon-art"]

    @Test func agentsFollowTheDefaultsUntilCustomized() {
        var settings = AgentSettings()
        #expect(settings.skills(for: "codex", shipped: shipped) == shipped)
        settings.defaultSkills = ["summon", "summon-art"]
        #expect(settings.skills(for: "codex", shipped: shipped) == ["summon", "summon-art"])
        #expect(!settings.isCustom("codex"))
        settings.setSkills(["summon"], for: "codex")
        #expect(settings.isCustom("codex"))
        #expect(settings.skills(for: "codex", shipped: shipped) == ["summon"])
        #expect(settings.skills(for: "claude", shipped: shipped) == ["summon", "summon-art"])
        settings.setSkills(nil, for: "codex")
        #expect(settings.skills(for: "codex", shipped: shipped) == ["summon", "summon-art"])
    }

    @Test func togglingBackToTheDefaultsFollowsThemAgain() {
        var settings = AgentSettings()
        settings.defaultSkills = ["summon"]
        let custom = settings.skills(for: "pi", shipped: shipped, turning: "mac-app", on: true)
        #expect(custom == ["mac-app", "summon"])
        settings.setSkills(custom, for: "pi")
        #expect(settings.skills(for: "pi", shipped: shipped, turning: "mac-app", on: false) == nil)
        #expect(settings.defaultSkills(shipped: shipped, turning: "mac-app", on: true) == ["mac-app", "summon"])
        #expect(AgentSettingsCommand.defaultSkills(nil) == ["agents", "defaults", "--all-skills"])
        #expect(AgentSettingsCommand.defaultSkills(["summon"]) == ["agents", "defaults", "--skills=summon"])
    }

    @Test func oldFilesWithoutDefaultsStillDecode() throws {
        let data = Data(#"{"agents":{"codex":{"model":"o3"}}}"#.utf8)
        let settings = try JSONDecoder().decode(AgentSettings.self, from: data)
        #expect(settings.defaultSkills == nil)
        #expect(settings.model(for: "codex") == "o3")
    }
}
