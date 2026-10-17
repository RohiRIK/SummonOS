import Foundation
import Testing
@testable import SummonCore

@Suite("Agents and launching")
struct AgentTests {
    @Test func claudeRunsInAutoModeAndTakesPromptAfterDashDash() throws {
        let claude = try #require(AgentRegistry.find("claude"))
        #expect(claude.argv(prompt: nil) == ["claude", "--permission-mode", "auto"])
        #expect(claude.argv(prompt: "-v is a prompt") == ["claude", "--permission-mode", "auto", "--", "-v is a prompt"])
        #expect(claude.argv(prompt: "") == claude.interactive)
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

    @Test func launchFromHomeStartsInWork() {
        #expect(AgentLauncher.workingDirectory(current: "/Users/a", home: "/Users/a", workExists: true) == "/Users/a/Work")
        #expect(AgentLauncher.workingDirectory(current: "/Users/a/", home: "/Users/a", workExists: true) == "/Users/a/Work")
        #expect(AgentLauncher.workingDirectory(current: "/Users/a", home: "/Users/a", workExists: false) == "/Users/a")
        #expect(AgentLauncher.workingDirectory(current: "/Users/a/code", home: "/Users/a", workExists: true) == "/Users/a/code")
        // Launched from the menu bar app, whose folder is `/`.
        #expect(AgentLauncher.workingDirectory(current: "/", home: "/Users/a", workExists: true) == "/Users/a/Work")
        #expect(AgentLauncher.workingDirectory(current: "/", home: "/Users/a", workExists: false) == "/Users/a")
    }

    @Test func ghosttyPlanPassesArgvAfterDashE() {
        let plan = AgentLauncher.terminalPlan(agentArgv: ["/bin/claude", "--", "it's"], directory: "/tmp/x", terminal: .ghostty)
        #expect(plan.executable == "/usr/bin/open")
        #expect(plan.arguments == ["-na", "Ghostty", "--args", "--working-directory=/tmp/x", "-e", "/bin/claude", "--", "it's"])
    }

    @Test func terminalPlanNeverSplicesValuesIntoTheScript() {
        let hostile = "\"; do shell script \"rm -rf ~\" --"
        let plan = AgentLauncher.terminalPlan(agentArgv: ["/bin/claude", hostile], directory: "/tmp/x", terminal: .terminal)
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
        #expect(args.flag("--json"))
        #expect(!args.flag("--json"))
        #expect(args.option("--limit") == "3")
        #expect(args.next() == "list")
        #expect(args.items == ["rest"])

        var equals = Arguments(["--since=30m"])
        #expect(equals.option("--since") == "30m")
        #expect(equals.isEmpty)
    }
}
