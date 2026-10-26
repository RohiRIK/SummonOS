import Foundation
import Testing
@testable import SummonCore

@Suite("Updates: what every package manager says is outdated")
struct SoftwareUpdateTests {
    @Test func homebrewListsFormulaeAndCasksButNotPinned() {
        let json = """
        ==> Downloading Homebrew API data
        {"formulae": [{"name": "btop", "installed_versions": ["1.4.7"], "current_version": "1.4.8", "pinned": false},
                      {"name": "node@20", "installed_versions": ["20.1.0"], "current_version": "20.2.0", "pinned": true}],
         "casks": [{"name": "omniwm", "installed_versions": ["0.7.1"], "current_version": "0.7.6"}]}
        """
        let updates = SoftwareUpdate.homebrew(json, brew: "/opt/homebrew/bin/brew")
        #expect(updates.map(\.title) == ["btop 1.4.7", "omniwm 0.7.1"])
        #expect(updates.map(\.latest) == ["1.4.8", "0.7.6"])
        #expect(updates[0].command == ["/opt/homebrew/bin/brew", "upgrade", "btop"])
        #expect(updates[1].command == ["/opt/homebrew/bin/brew", "upgrade", "--cask", "omniwm"])
        #expect(SoftwareUpdate.homebrew("not json", brew: "b").isEmpty)
    }

    @Test func bunReadsItsTable() {
        let table = """
        bun outdated v1.3.14 (0d9b296a)
        |---------------------------------------------|
        | Package       | Current | Update  | Latest  |
        |---------------|---------|---------|---------|
        | \u{1B}[1m@openai/codex\u{1B}[0m | 0.158.0 | 0.158.0 | 0.164.0 |
        |---------------|---------|---------|---------|
        | opencode-ai   | 1.17.11 | 1.19.4  | 1.19.4  |
        |---------------------------------------------|
        """
        let updates = SoftwareUpdate.bun(table, bun: "/u/.bun/bin/bun")
        #expect(updates.map(\.title) == ["@openai/codex 0.158.0", "opencode-ai 1.17.11"])
        #expect(updates.map(\.latest) == ["0.164.0", "1.19.4"])
        #expect(updates[0].command == ["/u/.bun/bin/bun", "add", "-g", "@openai/codex@latest"])
    }

    @Test func npmReadsItsJSON() {
        let json = #"{"typescript": {"current": "5.4.0", "wanted": "5.4.0", "latest": "5.6.2"}, "same": {"current": "1.0.0", "latest": "1.0.0"}}\nnpm notice New major version of npm available!"#
        let updates = SoftwareUpdate.npm(json, npm: "/opt/homebrew/bin/npm")
        #expect(updates.map(\.title) == ["typescript 5.4.0"])
        #expect(updates[0].command == ["/opt/homebrew/bin/npm", "install", "-g", "typescript@latest"])
        #expect(SoftwareUpdate.npm("", npm: "n").isEmpty)
    }

    @Test func macOSReadsSoftwareUpdate() {
        let text = """
        Software Update Tool

        Finding available software
        Software Update found the following new or updated software:
        * Label: macOS Tahoe 26.1-25B78
        \tTitle: macOS Tahoe 26.1, Version: 26.1, Size: 3500000KiB, Recommended: YES, Action: restart,
        """
        let updates = SoftwareUpdate.macOS(text)
        #expect(updates.map(\.title) == ["macOS Tahoe 26.1"])
        #expect(updates[0].latest == "26.1")
        #expect(updates[0].command == nil)
        #expect(SoftwareUpdate.macOS("No new software available.").isEmpty)
    }

    @Test func checkSkipsMissingToolsAndKeepsOutputOfAFailingNpm() async {
        let log = CallLog()
        let npmJSON = #"{"typescript": {"current": "5.4.0", "latest": "5.6.2"}}"#
        let runner: Runner = { path, arguments in
            await log.add([path] + arguments)
            if path.hasSuffix("npm") { throw RunnerError.failed(path: path, status: 1, output: npmJSON) }
            return ""
        }
        let tools = ToolLocator(searchPath: ["/bin"], isExecutable: { $0 == "/bin/npm" })
        let updates = await SoftwareUpdateCheck(runner: runner, tools: tools).run()
        #expect(updates.map(\.name) == ["typescript"])
        #expect(Set(await log.calls.map(\.[0])) == ["/bin/npm", "/usr/sbin/softwareupdate"])
    }

    @Test func agentPackagesGetTheirOwnGroup() {
        let updates = SoftwareUpdate.markAgents([
            SoftwareUpdate(source: .bun, name: "@openai/codex", current: "1", latest: "2", command: ["bun", "add", "-g", "@openai/codex@latest"]),
            SoftwareUpdate(source: .homebrew, name: "claude-code", current: "1", latest: "2", command: ["brew"]),
            SoftwareUpdate(source: .homebrew, name: "btop", current: "1", latest: "2", command: ["brew"]),
        ])
        #expect(updates.map(\.group) == [.agents, .agents, .homebrew])
        #expect(updates.map(\.name) == ["Codex", "Claude Code", "btop"])
        #expect(updates[0].command == ["bun", "add", "-g", "@openai/codex@latest"])
    }

    @Test func updateFolderGroupsWhatIsOutdatedWithNewVersionTags() throws {
        let tree = try MenuTree(items: [MenuItem(id: "make", label: "Make"), MenuItem(id: "make.app", label: "App"),
                                        MenuItem(id: "update", label: "Update"),
                                        MenuItem(id: "update.brew", label: "Update Homebrew Apps", action: "x"),
                                        MenuItem(id: "apps", label: "My Apps")])
        let updates = [SoftwareUpdate(source: .summon, name: "Summon", current: "0.1.1", latest: "0.1.2", command: nil),
                       SoftwareUpdate(source: .homebrew, name: "btop", current: "1", latest: "2", command: ["brew"]),
                       SoftwareUpdate(source: .agent, name: "Codex", current: "1", latest: "2", command: ["bun"])]
        let filled = tree.withUpdates(updates)
        #expect(filled.items.map(\.id) == ["make", "make.app", "update", "update.0", "update.agents", "update.agents.2",
                                           "update.homebrew", "update.homebrew.1", "update.all", "update.check",
                                           "update.brew", "apps"])
        #expect(filled.item("update")?.badge == "3 new")
        #expect(filled.item("update.homebrew")?.badge == "1")
        #expect(filled.item("update.0")?.label == "Summon 0.1.1")
        #expect(filled.item("update.0")?.badge == "New 0.1.2")
        #expect(MenuTree.updateIndex("update.agents.2") == 2)
        #expect(MenuTree.updateIndex("update.brew") == nil)

        let none = try MenuTree(items: [MenuItem(id: "make", label: "Make")]).withUpdates([])
        #expect(none.items.map(\.id) == ["make", "update", "update.none", "update.check"])
        #expect(none.item("update")?.badge == nil)
    }
}
