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

    @Test func everyRowLinksToWhatIsNew() {
        let brew = SoftwareUpdate.homebrew(#"{"formulae": [{"name": "btop", "installed_versions": ["1"], "current_version": "2"}],"casks": [{"name": "omniwm", "installed_versions": ["1"], "current_version": "2"}]}"#, brew: "brew")
        #expect(brew.map(\.link) == ["https://formulae.brew.sh/formula/btop", "https://formulae.brew.sh/cask/omniwm"])
        #expect(SoftwareUpdate.npm(#"{"typescript": {"current": "1", "latest": "2"}}"#, npm: "npm")[0].link == "https://www.npmjs.com/package/typescript")
        #expect(SoftwareUpdate.summon(current: "0.2.0", latest: "0.2.1", tag: "v0.2.1").link
                == "https://github.com/RohiRIK/SummonOS/releases/tag/v0.2.1")
    }

    @Test func preferencesHideOffGroupsAndSkippedVersionsAndPersist() throws {
        let btop = SoftwareUpdate(source: .homebrew, name: "btop", current: "1", latest: "2", command: ["brew"])
        let codex = SoftwareUpdate(source: .agent, name: "Codex", current: "1", latest: "2", command: ["bun"])
        var preferences = UpdatePreferences()
        #expect(preferences.shown([btop, codex]) == [btop, codex])
        preferences.off = ["homebrew"]
        #expect(preferences.shown([btop, codex]) == [codex])
        preferences.off = []
        preferences.skipped[codex.id] = "2"
        #expect(preferences.shown([btop, codex]) == [btop])
        var newer = codex
        newer.latest = "3"
        #expect(preferences.shown([newer]) == [newer], "a newer version than the skipped one shows again")

        let store = UpdatePreferencesStore(paths: SummonPaths(home: try makeTempHome()))
        #expect(store.load() == UpdatePreferences())
        preferences.autoUpdateAgents = true
        try store.save(preferences)
        #expect(store.load() == preferences)
    }

    @Test func aPasswordFailureOffersTheTerminal() {
        #expect(UpdateRowState.failed("sudo: a terminal is required to read the password").needsTerminal)
        #expect(!UpdateRowState.failed("Error: No such keg").needsTerminal)
        #expect(!UpdateRowState.running.needsTerminal)
    }

    @Test func fixPromptCarriesTheCommandAndTheOutputTail() {
        let update = SoftwareUpdate(source: .homebrew, name: "notion", current: "7.10.0", latest: "7.41.1",
                                    command: ["/opt/homebrew/bin/brew", "upgrade", "--cask", "notion"])
        let prompt = update.fixPrompt(output: String(repeating: "x", count: 5000) + "Error: It seems there is already an App")
        #expect(prompt.contains("notion (Homebrew) from 7.10.0 to 7.41.1"))
        #expect(prompt.contains("/opt/homebrew/bin/brew upgrade --cask notion"))
        #expect(prompt.contains("Error: It seems there is already an App"))
        #expect(prompt.count < 4500, "only the end of a long output")
    }

    @Test func spokenUpdatesNameTheFirstThree() {
        let rows = ["btop", "notion", "omniwm", "npm"].map {
            SoftwareUpdate(source: .homebrew, name: $0, current: "1", latest: "2", command: nil)
        }
        #expect(SoftwareUpdate.spoken([]) == "Everything is up to date.")
        #expect(SoftwareUpdate.spoken(Array(rows.prefix(1))) == "1 update: btop.")
        #expect(SoftwareUpdate.spoken(rows) == "4 updates: btop, notion, omniwm and 1 more.")
    }

    @Test func panelUpdateRowIsTaggedAndOpensTheWindow() throws {
        let tree = try MenuTree(items: [MenuItem(id: "make", label: "Make"), MenuItem(id: "make.app", label: "App"),
                                        MenuItem(id: "apps", label: "My Apps")])
        let tagged = tree.withUpdates(count: 3)
        #expect(tagged.items.map(\.id) == ["make", "make.app", "update", "apps"])
        #expect(tagged.item("update")?.badge == "3 new")
        #expect(tagged.item("update")?.isRunnable == true, "choosing Update must do something")
        #expect(tree.withUpdates(count: 0).item("update")?.badge == nil)
        let custom = try MenuTree(items: [MenuItem(id: "update", label: "Update"), MenuItem(id: "update.macos", label: "macOS", action: "open x")])
        #expect(custom.withUpdates(count: 1).items.map(\.id) == ["update", "update.macos"])
        #expect(MenuTree.runsInApp("update") && !MenuTree.runsInApp("update.macos"))
    }
}
