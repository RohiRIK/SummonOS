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

extension AgentSettings {
    /// The agent's skill list after turning `name` on or off; nil when every shipped skill ends up on,
    /// so the agent keeps getting new skills as they ship.
    public func skills(for id: String, shipped: [String], turning name: String, on: Bool) -> [String]? {
        var chosen = Set(skills(for: id, shipped: shipped))
        if on { chosen.insert(name) } else { chosen.remove(name) }
        let result = shipped.filter(chosen.contains)
        return result == shipped ? nil : result
    }
}

/// `summon agents set` arguments, so the app changes `agents.json` through the CLI (which also relinks skills)
/// instead of writing the file itself. `=` forms keep a value starting with `-` from reading as a flag.
public enum AgentSettingsCommand {
    public static func model(_ model: String?, for id: String) -> [String] {
        let trimmed = model?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty
            ? ["agents", "set", id, "--default-model"]
            : ["agents", "set", id, "--model=" + trimmed]
    }

    /// nil puts the agent back on every shipped skill; an empty list gives it none.
    public static func skills(_ skills: [String]?, for id: String) -> [String] {
        guard let skills else { return ["agents", "set", id, "--all-skills"] }
        return ["agents", "set", id, "--skills=" + skills.joined(separator: ",")]
    }

    /// Skill names from `summon skills` output (one `…/<name>/SKILL.md` path per line), sorted.
    public static func skillNames(fromList output: String) -> [String] {
        let names = output.split(separator: "\n").compactMap { line -> String? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "/")
            guard parts.count >= 2, parts.last == "SKILL.md" else { return nil }
            return String(parts[parts.count - 2])
        }
        return Array(Set(names)).sorted()
    }
}
