import Foundation
import Testing
@testable import SummonCore

@Suite("Agent install and update")
struct AgentInstallTests {
    let home = "/Users/me"

    private func agent(_ id: String) throws -> Agent { try #require(AgentRegistry.find(id)) }

    @Test(arguments: [
        ("/opt/homebrew/Cellar/opencode/1.15.0/bin/opencode", InstallMethod.brew, "opencode"),
        ("/usr/local/Cellar/opencode/1.15.0/bin/opencode", .brew, "opencode"),
        ("/opt/homebrew/Caskroom/claude-code/2.1.308/claude", .brewCask, "claude-code"),
        ("/opt/homebrew/Caskroom/codex/0.164.0/codex-aarch64-apple-darwin", .brewCask, "codex"),
    ])
    func detectsHomebrew(path: String, method: InstallMethod, name: String) {
        let detected = DetectedInstall.detect(resolvedPath: path, home: home)
        #expect(detected.method == method)
        #expect(detected.brewName == name)
    }

    @Test(arguments: [
        ("/Users/me/.bun/install/global/node_modules/@openai/codex/bin/codex.js", InstallMethod.bun),
        ("/Users/me/.bun/bin/pi", .bun),
        ("/opt/homebrew/lib/node_modules/@github/copilot/index.js", .npm),
        ("/Users/me/.nvm/versions/node/v22.1.0/lib/node_modules/@openai/codex/bin/codex.js", .npm),
        ("/Users/me/.local/share/fnm/node-versions/v22/installation/lib/node_modules/opencode-ai/bin/opencode", .npm),
        ("/Users/me/.volta/bin/volta-shim", .npm),
        ("/Users/me/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js", .npm),
        ("/Users/me/.local/share/claude/versions/2.1.310", .vendor),
        ("/Users/me/.local/bin/cursor-agent", .vendor),
        ("/Users/me/.opencode/bin/opencode", .vendor),
        ("/usr/local/bin/grok", .unknown),
    ])
    func detectsOtherMethods(path: String, method: InstallMethod) {
        let detected = DetectedInstall.detect(resolvedPath: path, home: home)
        #expect(detected.method == method)
        #expect(detected.brewName == nil)
    }

    @Test func detectResolvesSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("summon-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Cellar/codex/1.0/bin/codex")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: real)
        let link = root.appendingPathComponent("bin/codex")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let detected = DetectedInstall.detect(binaryPath: link.path, home: "/nowhere")
        #expect(detected.method == .brew)
        #expect(detected.brewName == "codex")
    }

    // MARK: Command building

    private func finder(_ tools: [String]) -> (String) -> String? {
        { name in tools.contains(name) ? "/bin/\(name)" : nil }
    }

    @Test func newNpmAgentInstallsWithBun() throws {
        let step = try AgentInstallPlan.install(agent("pi"), find: finder(["bun", "npm"]))
        #expect(step == InstallStep(executable: "/bin/bun", arguments: ["add", "-g", "--trust", "@earendil-works/pi-coding-agent"]))
        #expect(!step.needsConfirmation)
    }

    @Test func newNpmAgentFallsBackToNpmWithoutBun() throws {
        let step = try AgentInstallPlan.install(agent("claude"), find: finder(["npm"]))
        #expect(step == InstallStep(executable: "/bin/npm", arguments: ["install", "-g", "@anthropic-ai/claude-code"]))
    }

    @Test func newNpmAgentStopsWithBunCommandWhenNeitherExists() throws {
        #expect(throws: AgentInstallError.needsBun(agent: "Codex")) {
            try AgentInstallPlan.install(agent("codex"), find: finder([]))
        }
        #expect(AgentInstallError.needsBun(agent: "Codex").description.contains("curl -fsSL https://bun.sh/install | bash"))
    }

    @Test func scriptOnlyAgentsUseTheVendorScriptAndNeedConfirmation() throws {
        for (id, url) in [("cursor-agent", "https://cursor.com/install"), ("grok", "https://x.ai/cli/install.sh"),
                          ("openclaw", "https://openclaw.ai/install.sh")] {
            let step = try AgentInstallPlan.install(agent(id), find: finder(["bun", "npm"]))
            #expect(step.executable == "/bin/bash")
            #expect(step.arguments == ["-c", "curl -fsSL \(url) | bash"])
            #expect(step.needsConfirmation)
            #expect(step.display == "curl -fsSL \(url) | bash")
        }
    }

    @Test func updatesFollowTheInstallMethod() throws {
        let find = finder(["brew", "bun", "npm"])
        func update(_ id: String, _ method: InstallMethod, _ brewName: String? = nil) throws -> InstallStep {
            try AgentInstallPlan.update(agent(id), agentPath: "/x/\(id)",
                                        detected: DetectedInstall(method: method, brewName: brewName, resolvedPath: "/x"), find: find)
        }
        #expect(try update("opencode", .brew, "opencode") == InstallStep(executable: "/bin/brew", arguments: ["upgrade", "opencode"]))
        #expect(try update("claude", .brewCask, "claude-code") == InstallStep(executable: "/bin/brew", arguments: ["upgrade", "--cask", "claude-code"]))
        #expect(try update("codex", .bun) == InstallStep(executable: "/bin/bun", arguments: ["add", "-g", "--trust", "@openai/codex@latest"]))
        #expect(try update("copilot", .npm) == InstallStep(executable: "/bin/npm", arguments: ["install", "-g", "@github/copilot@latest"]))
        #expect(try update("claude", .vendor) == InstallStep(executable: "/x/claude", arguments: ["update"]))
        #expect(try update("opencode", .vendor) == InstallStep(executable: "/x/opencode", arguments: ["upgrade"]))
        let rerun = try update("agy", .vendor)
        #expect(rerun.needsConfirmation && rerun.display == "curl -fsSL https://antigravity.google/cli/install.sh | bash")
        #expect(throws: AgentInstallError.cannotUpdate(agent: "Grok", method: .unknown)) { try update("grok", .unknown) }
        #expect(throws: AgentInstallError.cannotUpdate(agent: "Antigravity", method: .bun)) { try update("agy", .bun) }
        #expect(throws: AgentInstallError.missingTool("bun")) {
            try AgentInstallPlan.update(agent("pi"), agentPath: "/x/pi",
                                        detected: DetectedInstall(method: .bun, resolvedPath: "/x"), find: finder([]))
        }
    }

    @Test func noStepUsesSudo() throws {
        for agent in AgentRegistry.all {
            if let step = try? AgentInstallPlan.install(agent, find: finder(["bun"])) {
                #expect(!step.executable.hasSuffix("sudo") && !step.arguments.joined(separator: " ").contains("sudo"))
            }
        }
    }

    // MARK: Versions

    @Test func parsesTheFirstVersion() {
        #expect(AgentVersion.parse("2.1.310 (Claude Code)") == "2.1.310")
        #expect(AgentVersion.parse("codex-cli 0.158.0") == "0.158.0")
        #expect(AgentVersion.parse("opencode v2.1.4") == "2.1.4")
        #expect(AgentVersion.parse("2026.10.22-27dcf5f") == "2026.10.22")
        #expect(AgentVersion.parse("no version here") == nil)
    }

    @Test func comparesNumerically() {
        #expect(AgentVersion.isNewer("2.1.10", than: "2.1.9"))
        #expect(AgentVersion.isNewer("0.164.0", than: "0.158.0"))
        #expect(!AgentVersion.isNewer("1.0", than: "1.0.0"))
        #expect(!AgentVersion.isNewer("1.19.4", than: "2.1.4"))
    }

    @Test func parsesSources() {
        let brew = #"Warning: noise\n{"formulae":[{"name":"opencode","installed_versions":["1.0"],"current_version":"1.2"}],"casks":[{"name":"claude-code","installed_versions":["2.0"],"current_version":"2.1"}]}"#
        #expect(AgentUpdates.parseBrewOutdated(brew) == ["opencode": "1.2", "claude-code": "2.1"])
        #expect(AgentUpdates.parseBrewOutdated("not json") == nil)
        #expect(AgentUpdates.parseNpmLatest(#"{"name":"@openai/codex","version":"0.164.0"}"#) == "0.164.0")
    }

    // MARK: Check and cache

    private func makeUpdates(_ runner: @escaping Runner) -> (AgentUpdates, SummonPaths) {
        let paths = SummonPaths(home: FileManager.default.temporaryDirectory.appendingPathComponent("summon-updates-\(UUID().uuidString)"))
        let tools = ToolLocator(searchPath: ["/fake/bin"]) { ["/fake/bin/codex", "/fake/bin/claude", "/fake/bin/opencode", "/fake/bin/brew"].contains($0) }
        let methods: [String: DetectedInstall] = [
            "/fake/bin/codex": DetectedInstall(method: .bun, resolvedPath: "/b"),
            "/fake/bin/claude": DetectedInstall(method: .vendor, resolvedPath: "/v"),
            "/fake/bin/opencode": DetectedInstall(method: .brew, brewName: "opencode", resolvedPath: "/c"),
        ]
        return (AgentUpdates(paths: paths, runner: runner, tools: tools) { methods[$0] ?? DetectedInstall(method: .unknown, resolvedPath: $0) }, paths)
    }

    @Test func checkReportsEachMethodAndCachesForADay() async throws {
        let calls = Calls()
        let (updates, paths) = makeUpdates { path, arguments in
            await calls.add(path)
            switch (path, arguments.first) {
            case ("/fake/bin/codex", _): return "codex-cli 0.158.0"
            case ("/fake/bin/claude", _): return "2.1.310 (Claude Code)"
            case ("/fake/bin/opencode", _): return "1.15.0"
            case ("/fake/bin/brew", _): return #"{"formulae":[{"name":"opencode","current_version":"1.19.4"}],"casks":[]}"#
            case ("/usr/bin/curl", _): return #"{"version":"0.164.0"}"#
            default: throw RunnerError.failed(path: path, status: 1, output: "")
            }
        }
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(updates.cachedUpdateCount(now: now) == nil)
        let report = await updates.check(now: now)
        let byID = Dictionary(uniqueKeysWithValues: report.agents.map { ($0.id, $0) })
        #expect(byID["codex"]?.latest == "0.164.0" && byID["codex"]?.updateAvailable == true)
        #expect(byID["claude"]?.latest == nil && byID["claude"]?.updateAvailable == false)
        #expect(byID["opencode"]?.latest == "1.19.4" && byID["opencode"]?.updateAvailable == true)
        #expect(report.updateCount == 2)

        // Within 24 hours the cache answers without running anything.
        let before = await calls.count
        let again = await updates.check(now: now.addingTimeInterval(3600))
        #expect(again == report)
        #expect(await calls.count == before)
        #expect(updates.cachedUpdateCount(now: now.addingTimeInterval(3600)) == 2)
        #expect(updates.cachedUpdateCount(now: now.addingTimeInterval(25 * 3600)) == nil)
        _ = await updates.check(refresh: true, now: now.addingTimeInterval(3600))
        #expect(await calls.count > before)

        updates.markUpdated("codex")
        #expect(updates.cached()?.agents.first { $0.id == "codex" }?.updateAvailable == false)
        #expect(updates.cached()?.updateCount == 1)
    }

    @Test func offlineChecksClaimNoUpdate() async {
        let (updates, paths) = makeUpdates { path, _ in
            if path.hasPrefix("/fake/bin/") && !path.hasSuffix("brew") { return "1.0.0" }
            throw RunnerError.failed(path: path, status: 6, output: "offline")
        }
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let report = await updates.check(now: Date())
        #expect(report.updateCount == 0)
        #expect(report.agents.allSatisfy { $0.latest == nil })
    }
}

private actor Calls {
    private(set) var paths: [String] = []
    var count: Int { paths.count }
    func add(_ path: String) { paths.append(path) }
}
