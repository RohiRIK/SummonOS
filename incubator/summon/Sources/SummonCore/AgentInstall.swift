import Foundation

/// How Summon installs and updates one coding-agent CLI (owner decision 2026-10-25): new installs of agents
/// published on npm use bun; brew-only or script-only agents keep their own installer; an existing install is
/// always updated the way it was installed.
public struct AgentInstall: Sendable, Equatable {
    /// The npm package (checked on registry.npmjs.org); nil when the agent is not on npm.
    public var npmPackage: String?
    /// The vendor's install script, run as `curl -fsSL <url> | bash`; when set, new installs use it.
    public var vendorScript: String?
    /// Arguments after the agent's command for its own updater, only when verified with `<cmd> --help`.
    public var selfUpdate: [String]?

    public static let bunInstallCommand = "curl -fsSL https://bun.sh/install | bash"

    public static let catalog: [String: AgentInstall] = [
        "claude": AgentInstall(npmPackage: "@anthropic-ai/claude-code", selfUpdate: ["update"]),
        "codex": AgentInstall(npmPackage: "@openai/codex", selfUpdate: ["update"]),
        "opencode": AgentInstall(npmPackage: "opencode-ai", selfUpdate: ["upgrade"]),
        "copilot": AgentInstall(npmPackage: "@github/copilot"),
        "cursor-agent": AgentInstall(vendorScript: "https://cursor.com/install"),
        "agy": AgentInstall(vendorScript: "https://antigravity.google/cli/install.sh"),
        "pi": AgentInstall(npmPackage: "@earendil-works/pi-coding-agent"),
        "hermes": AgentInstall(vendorScript: "https://hermes-agent.nousresearch.com/install.sh"),
        // On npm too, so an npm or bun install updates there; new installs keep the vendor script.
        "openclaw": AgentInstall(npmPackage: "openclaw", vendorScript: "https://openclaw.ai/install.sh"),
        "grok": AgentInstall(vendorScript: "https://x.ai/cli/install.sh"),
    ]
}

extension Agent {
    public var install: AgentInstall { AgentInstall.catalog[id] ?? AgentInstall() }
}

/// How an installed agent got onto this Mac, read from where its binary really lives.
public enum InstallMethod: String, Codable, Sendable, Equatable {
    case brew, brewCask = "brew-cask", bun, npm, vendor, unknown
}

public struct DetectedInstall: Codable, Sendable, Equatable {
    public var method: InstallMethod
    /// The Homebrew formula or cask, for the brew methods.
    public var brewName: String?
    /// The binary with symlinks resolved.
    public var resolvedPath: String

    /// `resolvedPath` must already have symlinks resolved (see `detect(binaryPath:home:)`).
    public static func detect(resolvedPath path: String, home: String) -> DetectedInstall {
        let parts = path.split(separator: "/").map(String.init)
        func after(_ marker: String) -> String? {
            guard let index = parts.firstIndex(of: marker), index + 1 < parts.count else { return nil }
            return parts[index + 1]
        }
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        if let cask = after("Caskroom") { return DetectedInstall(method: .brewCask, brewName: cask, resolvedPath: path) }
        if let formula = after("Cellar") { return DetectedInstall(method: .brew, brewName: formula, resolvedPath: path) }
        if path.hasPrefix(home + "/.bun/") { return DetectedInstall(method: .bun, resolvedPath: path) }
        // npm's global prefix, wherever node came from (Homebrew, nvm, fnm, volta, ~/.npm-global).
        if parts.contains("node_modules") || [".nvm", ".volta", "fnm"].contains(where: parts.contains) {
            return DetectedInstall(method: .npm, resolvedPath: path)
        }
        // Vendor scripts install into the home folder: ~/.local/bin, ~/.local/share/claude, ~/.opencode/bin, ...
        if path.hasPrefix(home + "/") { return DetectedInstall(method: .vendor, resolvedPath: path) }
        return DetectedInstall(method: .unknown, resolvedPath: path)
    }

    public static func detect(binaryPath: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> DetectedInstall {
        detect(resolvedPath: URL(fileURLWithPath: binaryPath).resolvingSymlinksInPath().path, home: home)
    }
}

/// One command Summon runs to install or update an agent. Never sudo.
public struct InstallStep: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    /// True for a vendor install script piped to bash: off a terminal it needs `--yes`.
    public var needsConfirmation = false

    public var display: String {
        executable == "/bin/bash" && arguments.first == "-c" ? arguments[1] : ([executable] + arguments).joined(separator: " ")
    }
}

public enum AgentInstallError: Error, Equatable, CustomStringConvertible {
    case needsBun(agent: String)
    case missingTool(String)
    case cannotUpdate(agent: String, method: InstallMethod)
    case notInstalled(agent: String)

    public var description: String {
        switch self {
        case let .needsBun(agent):
            return "\(agent) installs with bun, and neither bun nor npm is on this Mac. Install bun first:\n  \(AgentInstall.bunInstallCommand)"
        case let .missingTool(tool):
            return "\(tool) is not on this Mac, so Summon cannot run it."
        case let .cannotUpdate(agent, method):
            return "\(agent) was installed by \(method == .unknown ? "an unknown method" : "its vendor") and has no verified updater; update it the way you installed it."
        case let .notInstalled(agent):
            return "\(agent) is not installed. Install it with: summon agents install"
        }
    }
}

public enum AgentInstallPlan {
    private static func script(_ url: String) -> InstallStep {
        InstallStep(executable: "/bin/bash", arguments: ["-c", "curl -fsSL \(url) | bash"], needsConfirmation: true)
    }

    /// A new install: bun for npm agents (npm if bun is missing), else the vendor script. bun gets `--trust` because it
    /// skips dependency postinstall scripts otherwise, and some agents (opencode-ai) fetch their binary there.
    public static func install(_ agent: Agent, find: (String) -> String?) throws -> InstallStep {
        let install = agent.install
        if let package = install.npmPackage, install.vendorScript == nil {
            if let bun = find("bun") { return InstallStep(executable: bun, arguments: ["add", "-g", "--trust", package]) }
            if let npm = find("npm") { return InstallStep(executable: npm, arguments: ["install", "-g", package]) }
            throw AgentInstallError.needsBun(agent: agent.name)
        }
        if let url = install.vendorScript { return script(url) }
        throw AgentInstallError.cannotUpdate(agent: agent.name, method: .unknown)
    }

    /// An update the same way the agent was installed.
    public static func update(_ agent: Agent, agentPath: String, detected: DetectedInstall,
                              find: (String) -> String?) throws -> InstallStep {
        func tool(_ name: String) throws -> String {
            guard let path = find(name) else { throw AgentInstallError.missingTool(name) }
            return path
        }
        let install = agent.install
        switch detected.method {
        case .brew:
            guard let name = detected.brewName else { break }
            return InstallStep(executable: try tool("brew"), arguments: ["upgrade", name])
        case .brewCask:
            guard let name = detected.brewName else { break }
            return InstallStep(executable: try tool("brew"), arguments: ["upgrade", "--cask", name])
        case .bun:
            guard let package = install.npmPackage else { break }
            return InstallStep(executable: try tool("bun"), arguments: ["add", "-g", "--trust", package + "@latest"])
        case .npm:
            guard let package = install.npmPackage else { break }
            return InstallStep(executable: try tool("npm"), arguments: ["install", "-g", package + "@latest"])
        case .vendor:
            if let selfUpdate = install.selfUpdate { return InstallStep(executable: agentPath, arguments: selfUpdate) }
            if let url = install.vendorScript { return script(url) }
        case .unknown:
            break
        }
        throw AgentInstallError.cannotUpdate(agent: agent.name, method: detected.method)
    }
}

/// Dotted version numbers, compared numerically (`2.1.10` > `2.1.9`; cursor's `2026.10.22-abc` reads as 2026.10.22).
public enum AgentVersion {
    public static func parse(_ text: String) -> String? {
        guard let range = text.range(of: #"\d+(\.\d+)+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

public struct AgentUpdateStatus: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var path: String
    public var method: InstallMethod
    public var brewName: String?
    public var current: String?
    /// nil when the source cannot tell (vendor installs, offline): no update is claimed then.
    public var latest: String?
    public var updateAvailable: Bool
}

public struct AgentUpdateReport: Codable, Sendable, Equatable {
    public var checkedAt: Date
    public var agents: [AgentUpdateStatus]

    public var updateCount: Int { agents.filter(\.updateAvailable).count }

    public func isFresh(now: Date = Date(), maxAge: TimeInterval = 24 * 3600) -> Bool {
        now.timeIntervalSince(checkedAt) >= 0 && now.timeIntervalSince(checkedAt) < maxAge
    }
}

/// Finds installed agents, how each was installed, and whether an update is out. Results are cached in
/// `~/.local/state/summon/agent-updates.json` so the app can show "N agent updates" without the network.
public struct AgentUpdates: Sendable {
    public let paths: SummonPaths
    public let runner: Runner
    public let tools: ToolLocator
    public var detect: @Sendable (String) -> DetectedInstall

    public init(paths: SummonPaths, runner: @escaping Runner, tools: ToolLocator,
                detect: (@Sendable (String) -> DetectedInstall)? = nil) {
        self.paths = paths
        self.runner = runner
        self.tools = tools
        let home = paths.home.path
        self.detect = detect ?? { DetectedInstall.detect(binaryPath: $0, home: home) }
    }

    /// Installed agents with their path and install method. No processes, no network.
    public func installed() -> [(agent: Agent, path: String, detected: DetectedInstall)] {
        AgentRegistry.all.compactMap { agent in
            tools.find(agent.command).map { (agent: agent, path: $0, detected: detect($0)) }
        }
    }

    /// The last saved check, fresh or not; nil when none is saved or it cannot be read.
    public func cached() -> AgentUpdateReport? {
        try? StateFile.load(AgentUpdateReport?.self, at: paths.agentUpdatesFile, default: nil, decoder: Self.decoder)
    }

    /// The cached update count when the cache is fresh (the app's badge); nil means "check needed".
    public func cachedUpdateCount(now: Date = Date()) -> Int? {
        guard let report = cached(), report.isFresh(now: now) else { return nil }
        return report.updateCount
    }

    /// The cached report when it is under 24 hours old, else a new check (versions + latest), saved to the cache.
    public func check(refresh: Bool = false, now: Date = Date()) async -> AgentUpdateReport {
        if !refresh, let report = cached(), report.isFresh(now: now) { return report }
        let installed = installed()
        let brewOutdated = installed.contains { [.brew, .brewCask].contains($0.detected.method) } ? await brewOutdatedVersions() : nil
        var rows: [AgentUpdateStatus] = []
        for (agent, path, detected) in installed {
            let current = (try? await runner(path, ["--version"])).flatMap(AgentVersion.parse)
            var latest: String?
            switch detected.method {
            case .brew, .brewCask:
                // Not in `brew outdated` means Homebrew has nothing newer.
                if let brewOutdated, let name = detected.brewName { latest = brewOutdated[name] ?? current }
            case .bun, .npm:
                if let package = agent.install.npmPackage { latest = await npmLatest(package) }
            case .vendor, .unknown:
                latest = nil
            }
            let available = current.flatMap { current in latest.map { AgentVersion.isNewer($0, than: current) } } ?? false
            rows.append(AgentUpdateStatus(id: agent.id, name: agent.name, path: path, method: detected.method,
                                          brewName: detected.brewName, current: current, latest: latest,
                                          updateAvailable: available))
        }
        let report = AgentUpdateReport(checkedAt: now, agents: rows)
        try? save(report)
        return report
    }

    /// After a successful install or update, the agent no longer counts as outdated in the cache.
    public func markUpdated(_ id: String) {
        guard var report = cached(), let index = report.agents.firstIndex(where: { $0.id == id }) else { return }
        report.agents[index].updateAvailable = false
        if let latest = report.agents[index].latest { report.agents[index].current = latest }
        try? save(report)
    }

    public func installStep(for agent: Agent) throws -> InstallStep {
        try AgentInstallPlan.install(agent, find: tools.find)
    }

    public func updateStep(for agent: Agent) throws -> InstallStep {
        guard let path = tools.find(agent.command) else { throw AgentInstallError.notInstalled(agent: agent.name) }
        return try AgentInstallPlan.update(agent, agentPath: path, detected: detect(path), find: tools.find)
    }

    private func save(_ report: AgentUpdateReport) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try TextFile.write(String(decoding: try encoder.encode(report), as: UTF8.self) + "\n", to: paths.agentUpdatesFile)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// `brew outdated --json=v2`: formula or cask name to the newer version.
    /// nil when brew could not answer, so no version is claimed.
    func brewOutdatedVersions() async -> [String: String]? {
        guard let brew = tools.find("brew"), let output = try? await runner(brew, ["outdated", "--json=v2"]) else { return nil }
        return Self.parseBrewOutdated(output)
    }

    static func parseBrewOutdated(_ json: String) -> [String: String]? {
        struct Entry: Decodable { let name: String; let current_version: String }
        struct Outdated: Decodable { let formulae: [Entry]?; let casks: [Entry]? }
        guard let start = json.firstIndex(of: "{"),
              let outdated = try? JSONDecoder().decode(Outdated.self, from: Data(json[start...].utf8)) else { return nil }
        var versions: [String: String] = [:]
        for entry in (outdated.formulae ?? []) + (outdated.casks ?? []) { versions[entry.name] = entry.current_version }
        return versions
    }

    /// The registry's `latest` tag, which both bun and npm install.
    func npmLatest(_ package: String) async -> String? {
        let url = "https://registry.npmjs.org/" + package.replacingOccurrences(of: "/", with: "%2F") + "/latest"
        guard let output = try? await runner("/usr/bin/curl", ["-fsSL", "--max-time", "10", url]) else { return nil }
        return Self.parseNpmLatest(output)
    }

    static func parseNpmLatest(_ json: String) -> String? {
        struct Latest: Decodable { let version: String }
        return (try? JSONDecoder().decode(Latest.self, from: Data(json.utf8)))?.version
    }
}
