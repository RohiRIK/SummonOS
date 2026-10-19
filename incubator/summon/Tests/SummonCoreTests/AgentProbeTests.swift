import Foundation
import Testing
@testable import SummonCore

@Suite("What each agent can report: login and models")
struct AgentProbeTests {
    func agent(_ id: String) throws -> Agent { try #require(AgentRegistry.find(id)) }

    @Test func claudeLoginFromJSON() throws {
        let out = #"{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty"}"#
        #expect(AgentProbe.login(try agent("claude"), output: out, ok: true) == .init(loggedIn: true, detail: "claude.ai"))
        #expect(AgentProbe.login(try agent("claude"), output: #"{"loggedIn": false}"#, ok: true).loggedIn == false)
        #expect(AgentProbe.models(try agent("claude"), output: "") == ["opus", "sonnet", "haiku"])
    }

    @Test func codexLoginFromText() throws {
        #expect(AgentProbe.login(try agent("codex"), output: "Logged in using ChatGPT\n", ok: true) == .init(loggedIn: true, detail: "ChatGPT"))
        #expect(AgentProbe.login(try agent("codex"), output: "Not logged in\n", ok: false).loggedIn == false)
    }

    @Test func opencodeCountsStoredProviders() throws {
        let out = "OpenCode Go     API key                     stored\nGitHub Copilot  OAuth                       stored\n"
        #expect(AgentProbe.login(try agent("opencode"), output: out, ok: true) == .init(loggedIn: true, detail: "2 providers"))
        #expect(AgentProbe.login(try agent("opencode"), output: "", ok: true).loggedIn == false)
    }

    @Test func antigravityModelsAndLogin() throws {
        let out = "Fetching available models...\ngemini-4-argon-medium\tGemini 4 Argon (Medium)\nclaude-opus-5-5-low\tClaude Opus 5.5 (Low)\n"
        #expect(AgentProbe.models(try agent("agy"), output: out) == ["gemini-4-argon-medium", "claude-opus-5-5-low"])
        #expect(AgentProbe.login(try agent("agy"), output: out, ok: true).loggedIn == true)
        #expect(AgentProbe.login(try agent("agy"), output: "You are not logged into Antigravity.", ok: false).loggedIn == false)
    }

    @Test func piModelsAndProviderLogin() throws {
        let table = """
            provider        model                     context  max-out  thinking  images
            anthropic       claude-fable-5            1M       128K     yes       yes
            google          gemini-4-argon            1M       64K      yes       yes
            """
        #expect(AgentProbe.models(try agent("pi"), output: table) == ["anthropic/claude-fable-5", "google/gemini-4-argon"])
        #expect(AgentProbe.login(try agent("pi"), output: #"{"status":"ready","provider":"anthropic","authType":"oauth"}"#, ok: true)
            == .init(loggedIn: true, detail: "anthropic"))
        #expect(AgentProbe.login(try agent("pi"), output: #"{"status":"not_ready","provider":"google","reason":"credentials_not_configured"}"#, ok: false)
            == .init(loggedIn: false, detail: "google"))
        #expect(AgentProbe.loginCheck(try agent("pi"), model: "anthropic/claude-fable-5")?.contains("anthropic") == true)
    }

    @Test func everyInstalledAgentHasALoginAction() throws {
        for id in ["claude", "codex", "opencode", "agy", "pi"] {
            #expect(AgentProbe.loginAction(try agent(id)).first == (try agent(id)).command)
        }
    }

    @Test func skillDescriptionsFromFrontmatter() {
        let folded = "---\nname: summon\ndescription: >\n  The entry point.\n  Routes requests.\n---\n# Body\n"
        #expect(SkillInfo.description(fromSkillFile: folded) == "The entry point. Routes requests.")
        let quoted = "---\nname: Art\ndescription: \"Generates images. USE WHEN drawing.\"\n---\n"
        #expect(SkillInfo.description(fromSkillFile: quoted) == "Generates images. USE WHEN drawing.")
        #expect(SkillInfo.description(fromSkillFile: "# no frontmatter") == nil)
    }
}

extension AgentProbeTests {
    @Test func userFoldersComeBeforeHomebrew() {
        let dirs = ToolLocator.live(environment: ["PATH": "/usr/bin"]).searchPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(dirs.firstIndex(of: home + "/.bun/bin")! < dirs.firstIndex(of: "/opt/homebrew/bin")!)
    }

    @Test func codexLineAfterNoise() throws {
        #expect(AgentProbe.login(try agent("codex"), output: "WARNING: x\nLogged in using ChatGPT\n", ok: true) == .init(loggedIn: true, detail: "ChatGPT"))
    }

    @Test func piChecksItsOwnDefaultProvider() throws {
        let home = try makeTempHome()
        try writeFile(#"{"defaultProvider": "opencode-go", "defaultModel": "qwen3.7-max"}"#, to: home.appendingPathComponent(".pi/agent/settings.json"))
        let provider = AgentProbe.piDefaultProvider(home: home)
        #expect(provider == "opencode-go")
        #expect(AgentProbe.loginCheck(try agent("pi"), model: nil, piDefaultProvider: provider)?.contains("opencode-go") == true)
        #expect(AgentProbe.loginCheck(try agent("pi"), model: "anthropic/claude-fable-5", piDefaultProvider: provider)?.contains("anthropic") == true)
    }
}
