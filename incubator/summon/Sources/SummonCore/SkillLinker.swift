import Foundation

/// Links Summon's shipped skills into every coding agent's skill folder, the way Omarchy's
/// `omarchy-provision-user` does: symlinks (so an app update reaches every agent), every skill folder (so shipping a
/// new skill needs no code change), and a real folder of the user's with the same name is left alone.
public struct SkillLinker: Sendable {
    /// Relative to home. `.agents/skills` is the shared standard (OpenCode, Codex); Antigravity's CLI reads only
    /// `.gemini/config/skills` (verified with agy 1.4.2: not `~/.antigravity`, `~/.gemini/skills` or
    /// `~/.gemini/antigravity/skills`). OpenCode also reads `.claude/skills`.
    public static let agentFolders = [".agents/skills", ".claude/skills", ".codex/skills", ".gemini/config/skills"]

    public struct Result: Sendable, Equatable {
        public var linked: [String] = []
        /// The user's own folders with a shipped skill's name, left in place.
        public var kept: [String] = []
    }

    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public func link(from source: URL) throws -> Result {
        let fm = FileManager.default
        var result = Result()
        let skills = Self.skillNames(in: source)
        for folder in Self.agentFolders {
            let dir = home.appendingPathComponent(folder, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in skills {
                let link = dir.appendingPathComponent(name)
                let target = source.appendingPathComponent(name).path
                if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
                    try fm.removeItem(at: link)
                } else if fm.fileExists(atPath: link.path) {
                    result.kept.append(link.path)
                    continue
                }
                try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target)
                result.linked.append(link.path)
            }
        }
        return result
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
