import Foundation

/// What an agent's own CLI says about it: whether it is logged in, and which models it offers.
/// Commands and parsers are per CLI and were checked against the real output (2026-10-19).
public struct AgentLogin: Sendable, Equatable, Codable {
    /// nil when the CLI cannot tell.
    public var loggedIn: Bool?
    /// Account kind, provider, or count ("claude.ai", "ChatGPT", "2 providers").
    public var detail: String?

    public init(loggedIn: Bool?, detail: String? = nil) {
        self.loggedIn = loggedIn
        self.detail = detail
    }
}

public struct AgentStatus: Sendable, Equatable, Codable {
    public var login: AgentLogin
    public var models: [String]

    public init(login: AgentLogin, models: [String]) {
        self.login = login
        self.models = models
    }
}

public enum AgentProbe {
    /// Claude Code has no list command; these aliases always resolve to the current models.
    static let claudeModels = ["opus", "sonnet", "haiku"]

    /// argv that reports login state; nil when the model list doubles as the check (Antigravity).
    public static func loginCheck(_ agent: Agent, model: String?, piDefaultProvider: String? = nil) -> [String]? {
        switch agent.id {
        case "claude": return ["claude", "auth", "status"]
        case "codex": return ["codex", "login", "status"]
        case "opencode": return ["opencode", "auth", "list"]
        case "pi":
            // Pi logs in per provider: the chosen model's, else Pi's own default (~/.pi/agent/settings.json), else google.
            let provider = model.flatMap { $0.contains("/") ? $0.split(separator: "/").first.map(String.init) : nil }
                ?? piDefaultProvider ?? "google"
            return ["pi", "auth", "check", "--provider", provider, "--json", "--no-refresh"]
        default: return nil
        }
    }

    /// Pi's `defaultProvider` from `~/.pi/agent/settings.json`.
    public static func piDefaultProvider(home: URL) -> String? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".pi/agent/settings.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["defaultProvider"] as? String
    }

    /// argv that lists models; nil when there is no list command or no model option to use it with.
    public static func modelList(_ agent: Agent) -> [String]? {
        switch agent.id {
        case "agy": return ["agy", "models"]
        case "pi": return ["pi", "--list-models"]
        default: return nil
        }
    }

    /// What to run in a terminal so the user can log in.
    public static func loginAction(_ agent: Agent) -> [String] {
        switch agent.id {
        case "claude": return ["claude", "auth", "login"]
        case "codex": return ["codex", "login"]
        case "opencode": return ["opencode", "auth", "login"]
        default: return [agent.command]  // Antigravity and Pi log in from their own first screen (`/login` in Pi)
        }
    }

    public static func login(_ agent: Agent, output: String, ok: Bool) -> AgentLogin {
        switch agent.id {
        case "claude":
            guard let object = json(output) else { return AgentLogin(loggedIn: nil) }
            let loggedIn = object["loggedIn"] as? Bool
            return AgentLogin(loggedIn: loggedIn, detail: loggedIn == true ? object["authMethod"] as? String : nil)
        case "codex":
            // Read the "Logged in using …" line wherever it is: stderr noise may come first.
            guard ok, let line = output.split(separator: "\n").first(where: { $0.lowercased().hasPrefix("logged in") }) else {
                return AgentLogin(loggedIn: false)
            }
            let via = line.components(separatedBy: " using ").dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) }
            return AgentLogin(loggedIn: true, detail: via)
        case "opencode":
            let stored = output.split(separator: "\n").filter { $0.hasSuffix("stored") }.count
            return stored > 0 ? AgentLogin(loggedIn: true, detail: "\(stored) provider\(stored == 1 ? "" : "s")") : AgentLogin(loggedIn: false)
        case "agy":
            if output.contains("not logged in") { return AgentLogin(loggedIn: false) }
            return AgentLogin(loggedIn: ok && !models(agent, output: output).isEmpty ? true : nil)
        case "pi":
            guard let object = json(output) else { return AgentLogin(loggedIn: nil) }
            return AgentLogin(loggedIn: object["status"] as? String == "ready", detail: object["provider"] as? String)
        default:
            return AgentLogin(loggedIn: nil)
        }
    }

    public static func models(_ agent: Agent, output: String) -> [String] {
        switch agent.id {
        case "claude":
            return claudeModels
        case "agy":
            // `id<TAB>Display name` per line, after a "Fetching…" line.
            return output.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t")
                return parts.count >= 2 ? String(parts[0]).trimmingCharacters(in: .whitespaces) : nil
            }
        case "pi":
            // A table: provider, model, context… after a header row; Pi's --model takes provider/model.
            return output.split(separator: "\n").dropFirst().compactMap { line in
                let columns = line.split(separator: " ", omittingEmptySubsequences: true)
                return columns.count >= 2 ? "\(columns[0])/\(columns[1])" : nil
            }
        default:
            return []
        }
    }

    static func json(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
    }
}

/// A shipped skill's name and the `description` from its SKILL.md frontmatter, for Settings.
public struct SkillInfo: Sendable, Equatable, Codable {
    public var name: String
    public var description: String?

    public init(name: String, description: String?) {
        self.name = name
        self.description = description
    }

    /// `description: text`, a quoted value, or a folded/literal block (`>` / `|`) of indented lines.
    public static func description(fromSkillFile text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return nil }
        let front = Array(lines[1..<end])
        guard let index = front.firstIndex(where: { $0.hasPrefix("description:") }) else { return nil }
        var value = front[index].dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
        if [">", "|", ">-", "|-"].contains(value) {
            value = front[(index + 1)...].prefix { $0.hasPrefix(" ") || $0.isEmpty }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        } else if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}
