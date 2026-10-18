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
        var result = Result()
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
                    if isLink, isOurs(link, name: name) { try fm.removeItem(at: link) }
                    continue
                }
                if isLink {
                    try fm.removeItem(at: link)
                } else if fm.fileExists(atPath: link.path) {
                    result.kept.append(link.path)
                    continue
                }
                try fm.createSymbolicLink(atPath: link.path, withDestinationPath: source.appendingPathComponent(name).path)
                result.linked.append(link.path)
            }
        }
        for folder in Self.retiredFolders {
            for name in shipped {
                let link = home.appendingPathComponent(folder).appendingPathComponent(name)
                if isOurs(link, name: name) { try fm.removeItem(at: link) }
            }
        }
        return result
    }

    /// A symlink to some Summon install's copy of this skill (`…/share/summon/skills/<name>`), not the user's own.
    func isOurs(_ link: URL, name: String) -> Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return target.hasSuffix("/share/summon/skills/" + name) || target.hasSuffix("/plugin/skills/" + name)
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
