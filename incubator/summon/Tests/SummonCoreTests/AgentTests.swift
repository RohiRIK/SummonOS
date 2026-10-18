import Foundation
import Testing
@testable import SummonCore

@Suite("Agents and launching")
struct AgentTests {
    @Test func claudeSkipsPermissionsAndTakesPromptAfterDashDash() throws {
        let claude = try #require(AgentRegistry.find("claude"))
        #expect(claude.argv(prompt: nil) == ["claude", "--dangerously-skip-permissions"])
        #expect(claude.argv(prompt: "-v is a prompt") == ["claude", "--dangerously-skip-permissions", "--", "-v is a prompt"])
        #expect(claude.argv(prompt: "") == claude.interactive)
    }

    @Test func piTakesThePromptAfterDashDash() throws {
        let pi = try #require(AgentRegistry.find("pi"))
        #expect(pi.argv(prompt: nil) == ["pi"])
        #expect(pi.argv(prompt: "-v is a prompt") == ["pi", "--", "-v is a prompt"])
    }

    @Test func codexBypassesApprovalsAndSandbox() throws {
        let codex = try #require(AgentRegistry.find("codex"))
        #expect(codex.interactive == ["codex", "--dangerously-bypass-approvals-and-sandbox"])
    }

    @Test func aliasesResolve() {
        #expect(AgentRegistry.find("gemini")?.id == "agy")
        #expect(AgentRegistry.find("Claude-Code")?.id == "claude")
        #expect(AgentRegistry.find("cursor")?.id == "cursor-agent")
        #expect(AgentRegistry.find("nope") == nil)
    }

    @Test func idsAndAliasesAreUnique() {
        let names = AgentRegistry.all.flatMap { [$0.id] + $0.aliases }
        #expect(Set(names).count == names.count)
        for agent in AgentRegistry.all {
            #expect(agent.interactive.first == agent.command)
            #expect(agent.withPrompt.first == agent.command)
        }
    }

    @Test func defaultAgentRoundTrips() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let store = DefaultAgentStore(paths: paths)
        #expect(store.load() == nil)
        try store.save(try #require(AgentRegistry.find("codex")))
        #expect(store.load()?.id == "codex")
    }

    @Test func launchFromHomeStartsInTheProjectsFolder() {
        #expect(AgentLauncher.workingDirectory(current: "/u/a", home: "/u/a", projects: "/u/a/Summon") == "/u/a/Summon")
        #expect(AgentLauncher.workingDirectory(current: "/u/a/", home: "/u/a", projects: "/u/a/Summon/") == "/u/a/Summon")
        #expect(AgentLauncher.workingDirectory(current: "/u/a/code", home: "/u/a", projects: "/u/a/Summon") == "/u/a/code")
        // Launched from the menu bar app, whose folder is `/`.
        #expect(AgentLauncher.workingDirectory(current: "/", home: "/u/a", projects: "/u/a/Summon") == "/u/a/Summon")
    }

    @Test func ghosttyPlanOpensAWindowInTheRunningApp() {
        let plan = AgentLauncher.terminalPlan(agentArgv: ["/bin/claude", "--", "it's"], directory: "/tmp/x", terminal: .ghostty)
        #expect(plan.executable == "/usr/bin/osascript")
        let script = stride(from: 1, to: plan.arguments.count - 3, by: 2).map { plan.arguments[$0] }.joined(separator: "\n")
        // `open -na` started a second Ghostty per launch; a running one gets a window over AppleScript.
        #expect(script.contains("if application \"Ghostty\" is running then\ntell application \"Ghostty\""))
        #expect(script.contains("new window with configuration"))
    }

    @Test func kittyPlanHandsOffToTheRunningInstance() {
        let plan = AgentLauncher.terminalPlan(agentArgv: ["/bin/claude", "--", "it's"], directory: "/tmp/x", terminal: .kitty)
        #expect(plan.executable == "/usr/bin/open")
        #expect(plan.arguments == ["-na", "kitty", "--args", "--single-instance", "--directory", "/tmp/x", "/bin/claude", "--", "it's"])
    }

    @Test func savedTerminalWinsOnlyWhenInstalled() {
        let installed: Set<TerminalApp> = [.ghostty, .kitty, .terminal]
        #expect(AgentLauncher.preferredTerminal(saved: .kitty, installed: installed) == .kitty)
        #expect(AgentLauncher.preferredTerminal(saved: nil, installed: installed) == .ghostty)
        #expect(AgentLauncher.preferredTerminal(saved: .ghostty, installed: [.kitty, .terminal]) == .kitty)
        #expect(AgentLauncher.preferredTerminal(saved: .kitty, installed: [.terminal]) == .terminal)
    }

    @Test func terminalChoiceRoundTrips() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = DefaultTerminalStore(paths: SummonPaths(home: home))
        #expect(store.load() == nil)
        try store.save(.kitty)
        #expect(store.load() == .kitty)
    }

    @Test(arguments: [TerminalApp.ghostty, .terminal])
    func terminalPlanNeverSplicesValuesIntoTheScript(terminal: TerminalApp) {
        let hostile = "\"; do shell script \"rm -rf ~\" --"
        let plan = AgentLauncher.terminalPlan(agentArgv: ["/bin/claude", hostile], directory: "/tmp/x", terminal: terminal)
        #expect(plan.executable == "/usr/bin/osascript")
        // Values only appear after the script lines, as argv.
        #expect(Array(plan.arguments.suffix(3)) == ["/tmp/x", "/bin/claude", hostile])
        let scriptLines = stride(from: 1, to: plan.arguments.count - 3, by: 2).map { plan.arguments[$0] }
        #expect(!scriptLines.contains { $0.contains("rm -rf") || $0.contains("/tmp/x") })
    }

    @Test func toolLocatorSearchesInOrder() {
        let locator = ToolLocator(searchPath: ["/a", "/b"]) { $0 == "/b/claude" || $0 == "/a/git" }
        #expect(locator.find("claude") == "/b/claude")
        #expect(locator.find("git") == "/a/git")
        #expect(locator.find("missing") == nil)
        #expect(locator.find("/b/claude") == "/b/claude")
    }

    @Test func argumentsTakeFlagsAnywhere() {
        var args = Arguments(["list", "--limit", "3", "--json", "rest"])
        let first = args.flag("--json")
        let second = args.flag("--json")
        let limit = args.option("--limit")
        let command = args.next()
        #expect(first)
        #expect(!second)
        #expect(limit == "3")
        #expect(command == "list")
        #expect(args.items == ["rest"])

        var equals = Arguments(["--since=30m"])
        let since = equals.option("--since")
        #expect(since == "30m")
        #expect(equals.isEmpty)
    }
}
