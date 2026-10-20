import Foundation

/// Links Summon's shipped skills into every coding agent's skill folder, the way Omarchy's
/// `omarchy-provision-user` does: symlinks (so an app update reaches every agent), every skill folder (so shipping a
/// new skill needs no code change), and a real folder of the user's with the same name is left alone.
public struct SkillLinker: Sendable {
    /// Each agent's own folder (from `AgentRegistry`), so a skill can go to one agent and not another:
    /// Claude `.claude/skills`, Codex `.codex/skills`, OpenCode `.config/opencode/skills`, Antigravity
    /// `.gemini/config/skills` (verified: not `~/.antigravity`), Pi `.pi/agent/skills`. OpenCode also reads
    /// `.claude/skills`, so it sees Claude's choice too. The shared `.agents/skills` is not used: it would hand every
    /// skill to every agent that reads it.
    public static var agentFolders: [String] {
        AgentRegistry.all.compactMap(\.skillFolder)
    }

    /// Folders Summon linked into before per-agent choices; its links there are removed.
    static let retiredFolders = [".agents/skills"]

    public struct Result: Sendable, Equatable {
        public var linked: [String] = []
        /// The user's own folders with a shipped skill's name, left in place.
        public var kept: [String] = []
    }

    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public func link(from source: URL, settings: AgentSettings) throws -> Result {
        let fm = FileManager.default
        let lease = try FileLease.acquireSync(home.appendingPathComponent(".local/state/summon/locks/skills.lock"))
        defer { lease.hold() }
        var result = Result()
        var owned = try loadOwnership()
        let shipped = Self.skillNames(in: source)
        for agent in AgentRegistry.all {
            guard let folder = agent.skillFolder else { continue }
            let dir = home.appendingPathComponent(folder, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let chosen = Set(settings.skills(for: agent.id, shipped: shipped))
            for name in shipped {
                let link = dir.appendingPathComponent(name)
                let isLink = (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil
                if !chosen.contains(name) {
                    if isLink, isOurs(link, name: name, source: source, owned: owned) {
                        try fm.removeItem(at: link)
                        owned.removeValue(forKey: link.path)
                    }
                    continue
                }
                if isLink {
                    guard isOurs(link, name: name, source: source, owned: owned) else {
                        result.kept.append(link.path)
                        owned.removeValue(forKey: link.path)
                        continue
                    }
                    try fm.removeItem(at: link)
                } else if fm.fileExists(atPath: link.path) {
                    result.kept.append(link.path)
                    continue
                }
                try fm.createSymbolicLink(atPath: link.path, withDestinationPath: source.appendingPathComponent(name).path)
                owned[link.path] = source.appendingPathComponent(name).path
                result.linked.append(link.path)
            }
        }
        for folder in Self.retiredFolders {
            for name in shipped {
                let link = home.appendingPathComponent(folder).appendingPathComponent(name)
                if isOurs(link, name: name, source: source, owned: owned) {
                    try fm.removeItem(at: link)
                    owned.removeValue(forKey: link.path)
                }
            }
        }
        try TextFile.write(String(decoding: JSONEncoder().encode(owned), as: UTF8.self), to: ownershipFile)
        return result
    }

    var ownershipFile: URL { home.appendingPathComponent(".local/state/summon/skill-links.json") }

    private func loadOwnership() throws -> [String: String] {
        do {
            return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: ownershipFile))
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        }
    }

    /// Only an unchanged recorded link, the current source, or an exact known installation can be updated.
    /// A matching suffix alone also matches unrelated users' plugins and cannot establish ownership.
    func isOurs(_ link: URL, name: String) -> Bool {
        isOurs(link, name: name, source: nil, owned: (try? loadOwnership()) ?? [:])
    }

    private func isOurs(_ link: URL, name: String, source: URL?, owned: [String: String]) -> Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        if owned[link.path] == target { return true }
        guard target.hasPrefix("/") else { return false }
        let knownSources = [source, URL(fileURLWithPath: "/Applications/Summon.app/Contents/share/summon/skills"),
                            home.appendingPathComponent("Applications/Summon.app/Contents/share/summon/skills")].compactMap { $0 }
        return knownSources.contains { $0.appendingPathComponent(name).standardizedFileURL.path == URL(fileURLWithPath: target).standardizedFileURL.path }
    }

    /// Folders under `source` that hold a `SKILL.md`, sorted.
    public static func skillNames(in source: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
        return names
            .filter { FileManager.default.fileExists(atPath: source.appendingPathComponent("\($0)/SKILL.md").path) }
            .sorted()
    }

    /// Absolute `SKILL.md` paths, for prompts to agents whose harness has no skill mechanism.
    public static func skillFiles(in source: URL) -> [String] {
        skillNames(in: source).map { source.appendingPathComponent("\($0)/SKILL.md").path }
    }
}
