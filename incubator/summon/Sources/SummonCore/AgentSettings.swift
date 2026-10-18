import Foundation

/// Per-agent choices: the model to launch with and which Summon skills the agent gets.
/// Missing entries mean "the CLI's own default model" and "every shipped skill".
public struct AgentSettings: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public var model: String?
        /// Skill names; nil means every shipped skill.
        public var skills: [String]?
    }

    public var agents: [String: Entry] = [:]

    public init() {}

    public func model(for id: String) -> String? {
        agents[id]?.model
    }

    public func skills(for id: String, shipped: [String]) -> [String] {
        guard let chosen = agents[id]?.skills else { return shipped }
        return shipped.filter(chosen.contains)
    }

    public mutating func setModel(_ model: String?, for id: String) {
        let trimmed = model?.trimmingCharacters(in: .whitespaces)
        agents[id, default: Entry()].model = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// nil puts the agent back on every shipped skill.
    public mutating func setSkills(_ skills: [String]?, for id: String) {
        agents[id, default: Entry()].skills = skills?.sorted()
    }
}

/// `~/.config/summon/agents.json`, so the app, the CLI and agents themselves share one file.
public struct AgentSettingsStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    /// A missing or unreadable file means defaults; the user's file is never overwritten on a read.
    public func load() -> AgentSettings {
        guard let data = try? Data(contentsOf: paths.agentSettingsFile),
              let settings = try? JSONDecoder().decode(AgentSettings.self, from: data) else { return AgentSettings() }
        return settings
    }

    public func save(_ settings: AgentSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try TextFile.write(String(decoding: try encoder.encode(settings), as: UTF8.self) + "\n", to: paths.agentSettingsFile)
    }
}
