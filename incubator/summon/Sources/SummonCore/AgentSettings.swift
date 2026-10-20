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
    /// All Agents: the skills an agent gets unless its own page customizes them; nil means every shipped skill.
    public var defaultSkills: [String]? = nil

    public init() {}

    enum CodingKeys: String, CodingKey { case agents, defaultSkills }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agents = try container.decodeIfPresent([String: Entry].self, forKey: .agents) ?? [:]
        defaultSkills = try container.decodeIfPresent([String].self, forKey: .defaultSkills)
    }

    /// The All Agents skills.
    public func defaultSkills(shipped: [String]) -> [String] {
        guard let defaultSkills else { return shipped }
        return shipped.filter(defaultSkills.contains)
    }

    /// The agent has its own skill list instead of following All Agents.
    public func isCustom(_ id: String) -> Bool {
        agents[id]?.skills != nil
    }

    public func model(for id: String) -> String? {
        agents[id]?.model
    }

    public func skills(for id: String, shipped: [String]) -> [String] {
        guard let chosen = agents[id]?.skills else { return defaultSkills(shipped: shipped) }
        return shipped.filter(chosen.contains)
    }

    public mutating func setModel(_ model: String?, for id: String) {
        let trimmed = model?.trimmingCharacters(in: .whitespaces)
        agents[id, default: Entry()].model = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// nil puts the agent back on the All Agents skills.
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

    /// Display fallback only. Execution and mutations use loadValidated to preserve corrupt state.
    public func load() -> AgentSettings {
        (try? loadValidated()) ?? AgentSettings()
    }

    public func loadValidated() throws -> AgentSettings {
        try StateFile.load(AgentSettings.self, at: paths.agentSettingsFile, default: AgentSettings())
    }

    public func save(_ settings: AgentSettings) throws {
        let lease = try FileLease.acquireSync(paths.state.appendingPathComponent("locks/agents.lock"))
        defer { lease.hold() }
        _ = try loadValidated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try TextFile.write(String(decoding: try encoder.encode(settings), as: UTF8.self) + "\n", to: paths.agentSettingsFile)
    }
}

extension AgentSettings {
    /// The agent's skill list after turning `name` on or off; nil when it ends up equal to All Agents, so the agent
    /// follows the defaults again (and keeps getting what they get).
    public func skills(for id: String, shipped: [String], turning name: String, on: Bool) -> [String]? {
        var chosen = Set(skills(for: id, shipped: shipped))
        if on { chosen.insert(name) } else { chosen.remove(name) }
        let result = shipped.filter(chosen.contains)
        return result == defaultSkills(shipped: shipped) ? nil : result
    }

    /// The All Agents list after turning `name` on or off; nil when every shipped skill is on (new ones included).
    public func defaultSkills(shipped: [String], turning name: String, on: Bool) -> [String]? {
        var chosen = Set(defaultSkills(shipped: shipped))
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

    /// `summon agents defaults`: nil means every shipped skill.
    public static func defaultSkills(_ skills: [String]?) -> [String] {
        guard let skills else { return ["agents", "defaults", "--all-skills"] }
        return ["agents", "defaults", "--skills=" + skills.joined(separator: ",")]
    }

    /// nil puts the agent back on the All Agents skills; an empty list gives it none.
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
