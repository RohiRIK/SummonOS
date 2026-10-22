import Foundation
import Testing
@testable import SummonCore

@Suite("Settings window: sections and agent settings through the CLI")
struct SettingsSectionTests {
    @Test func sidebarOrderAndTitles() {
        #expect(SettingsSection.allCases.map(\.title)
            == ["General", "Agents", "My Apps", "Terminal", "Notifications", "Appearance", "Tasks"])
        #expect(SettingsSection.initial == .general)
        #expect(Set(SettingsSection.allCases.map(\.id)).count == SettingsSection.allCases.count)
        #expect(SettingsSection.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    @Test func modelArgumentsUseTheCLI() {
        #expect(AgentSettingsCommand.model("opus", for: "claude") == ["agents", "set", "claude", "--model=opus"])
        #expect(AgentSettingsCommand.model("  ", for: "claude") == ["agents", "set", "claude", "--default-model"])
        #expect(AgentSettingsCommand.model(nil, for: "pi") == ["agents", "set", "pi", "--default-model"])
    }

    @Test func modelArgumentParsesBackIntoTheSameValue() {
        var args = Arguments(Array(AgentSettingsCommand.model("-weird", for: "claude").dropFirst(3)))
        #expect(args.option("--model") == "-weird")
        #expect(args.isEmpty)
    }

    @Test func skillArgumentsUseTheCLI() {
        #expect(AgentSettingsCommand.skills(nil, for: "codex") == ["agents", "set", "codex", "--all-skills"])
        #expect(AgentSettingsCommand.skills(["mac-app", "summon"], for: "codex")
            == ["agents", "set", "codex", "--skills=mac-app,summon"])
        var none = Arguments(Array(AgentSettingsCommand.skills([], for: "codex").dropFirst(3)))
        #expect(none.option("--skills") == "")
    }

    @Test func togglingSkillsFallsBackToEverySkill() {
        let shipped = ["mac-app", "summon", "summon-art"]
        var settings = AgentSettings()
        let off = settings.skills(for: "claude", shipped: shipped, turning: "summon-art", on: false)
        #expect(off == ["mac-app", "summon"])
        settings.setSkills(off, for: "claude")
        #expect(settings.skills(for: "claude", shipped: shipped, turning: "summon", on: false) == ["mac-app"])
        // Turning the last one back on means "every skill", so new skills keep reaching the agent.
        #expect(settings.skills(for: "claude", shipped: shipped, turning: "summon-art", on: true) == nil)
    }

    @Test func togglingRoundTripsThroughTheStore() throws {
        let store = AgentSettingsStore(paths: SummonPaths(home: try makeTempHome()))
        let shipped = ["mac-app", "summon"]
        var settings = store.load()
        settings.setSkills(settings.skills(for: "agy", shipped: shipped, turning: "mac-app", on: false), for: "agy")
        settings.setModel("gemini-3", for: "agy")
        try store.save(settings)
        let loaded = store.load()
        #expect(loaded == settings)
        #expect(loaded.skills(for: "agy", shipped: shipped) == ["summon"])
        #expect(loaded.model(for: "agy") == "gemini-3")
    }

    @Test func shippedSkillNamesFromTheSkillsList() {
        let output = """
        /Applications/Summon.app/Contents/share/summon/skills/summon/SKILL.md
        /Applications/Summon.app/Contents/share/summon/skills/mac-app/SKILL.md

        not a skill line
        """
        #expect(AgentSettingsCommand.skillNames(fromList: output) == ["mac-app", "summon"])
        #expect(AgentSettingsCommand.skillNames(fromList: "").isEmpty)
    }
}
