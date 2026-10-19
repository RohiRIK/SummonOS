import Foundation

/// One plugin (or package, extension) an agent has installed.
public struct InstalledPlugin: Sendable, Equatable, Codable, Identifiable {
    public var name: String
    public var version: String?
    /// nil when the agent does not say.
    public var enabled: Bool?

    public var id: String { name }

    public init(name: String, version: String?, enabled: Bool?) {
        self.name = name
        self.version = version
        self.enabled = enabled
    }
}

/// Each agent's own plugin system: how to list and how to add. Parsers are written against real output (2026-10-19).
/// Codex has MCP servers instead of plugins (listed read-only); OpenCode keeps plugins in `opencode.json`.
public enum AgentPlugins {
    public static func list(_ agent: Agent) -> [String]? {
        switch agent.id {
        case "claude": return ["claude", "plugin", "list"]
        case "agy": return ["agy", "plugin", "list"]
        case "pi": return ["pi", "list"]
        case "codex": return ["codex", "mcp", "list"]
        default: return nil
        }
    }

    /// argv that installs `spec` (Claude `name@marketplace`, Antigravity a local folder, Pi `npm:<pkg>`);
    /// nil for OpenCode (a config edit, see `addOpencodePlugin`) and agents without plugins.
    public static func install(_ agent: Agent, spec: String) -> [String]? {
        switch agent.id {
        case "claude": return ["claude", "plugin", "install", spec]
        case "agy": return ["agy", "plugin", "install", spec]
        case "pi": return ["pi", "install", spec]
        default: return nil
        }
    }

    public static func canAdd(_ agent: Agent) -> Bool {
        agent.id == "opencode" || install(agent, spec: "") != nil
    }

    public static func parse(_ agent: Agent, output: String) -> [InstalledPlugin] {
        let lines = output.split(separator: "\n").map(String.init)
        switch agent.id {
        case "claude":
            // "  ❯ name@marketplace", then indented "Version:" / "Status: ✔ enabled" lines.
            var plugins: [InstalledPlugin] = []
            for line in lines {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("❯ ") {
                    plugins.append(InstalledPlugin(name: String(text.dropFirst(2)), version: nil, enabled: nil))
                } else if !plugins.isEmpty, text.hasPrefix("Version:") {
                    plugins[plugins.count - 1].version = text.dropFirst("Version:".count).trimmingCharacters(in: .whitespaces)
                } else if !plugins.isEmpty, text.hasPrefix("Status:") {
                    plugins[plugins.count - 1].enabled = text.contains("✔")
                }
            }
            return plugins
        case "agy":
            // "- name (enabled, 4.0.1)"
            return lines.compactMap { line in
                guard line.hasPrefix("- "), let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")") else { return nil }
                let name = line[line.index(line.startIndex, offsetBy: 2)..<open].trimmingCharacters(in: .whitespaces)
                let parts = line[line.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return InstalledPlugin(name: name, version: parts.count > 1 ? parts[1] : nil, enabled: parts.first.map { $0 == "enabled" })
            }
        case "pi":
            // Two-space-indented sources ("  npm:pkg (filtered)"); four-space lines are their paths.
            return lines.compactMap { line in
                guard line.hasPrefix("  "), !line.hasPrefix("    ") else { return nil }
                let name = line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
                return name.isEmpty ? nil : InstalledPlugin(name: name, version: nil, enabled: nil)
            }
        case "codex":
            // A table: "Name  Command  …  Status  Auth"; the first column of each row after the header.
            return lines.dropFirst().compactMap { line in
                let columns = line.split(separator: " ", omittingEmptySubsequences: true)
                guard let name = columns.first else { return nil }
                return InstalledPlugin(name: String(name), version: nil, enabled: columns.contains("enabled") ? true : (columns.contains("disabled") ? false : nil))
            }
        default:
            return []
        }
    }

    static func opencodeConfig(home: URL) -> URL {
        home.appendingPathComponent(".config/opencode/opencode.json")
    }

    public static func opencodePlugins(home: URL) -> [InstalledPlugin] {
        guard let data = try? Data(contentsOf: opencodeConfig(home: home)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names = object["plugin"] as? [String] else { return [] }
        return names.map { InstalledPlugin(name: $0, version: nil, enabled: true) }
    }

    /// Appends to `plugin` in `~/.config/opencode/opencode.json`, keeping every other key; the previous file is
    /// kept next to it as `opencode.json.summon-backup`. Refuses a file that is not plain JSON rather than lose it.
    public static func addOpencodePlugin(_ spec: String, home: URL) throws {
        let file = opencodeConfig(home: home)
        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: file) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])
            }
            object = parsed
            try data.write(to: URL(fileURLWithPath: file.path + ".summon-backup"), options: .atomic)
        }
        var names = object["plugin"] as? [String] ?? []
        guard !names.contains(spec) else { return }
        names.append(spec)
        object["plugin"] = names
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

/// Plugins Summon knows across agents: one entry, the right build per agent.
public struct CatalogPlugin: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    /// Agent id → what that agent's install takes.
    public var builds: [String: String]

    /// Installed when the agent lists a plugin whose name matches the build (versions and `@latest` ignored).
    public func isInstalled(for agent: String, in plugins: [InstalledPlugin]) -> Bool {
        guard let build = builds[agent] else { return false }
        let key = Self.base(build)
        return plugins.contains { Self.base($0.name) == key }
    }

    static func base(_ spec: String) -> String {
        var text = spec.hasPrefix("npm:") ? String(spec.dropFirst(4)) : spec
        if text.hasSuffix("@latest") { text = String(text.dropLast("@latest".count)) }
        return text.lowercased()
    }
}

public enum PluginCatalog {
    public static let all: [CatalogPlugin] = [
        CatalogPlugin(
            id: "openltm", name: "OpenLTM",
            summary: "Long-term memory across sessions: recall before work, learn after.",
            builds: ["claude": "openltm@OpenLtm", "opencode": "@rohirik/opencode-ltm@latest", "pi": "npm:@rohirik/pi-ltm"]
        ),
    ]

    /// Hands a plugin that is not working to the agent, with what Summon knows.
    public static func fixPrompt(_ plugin: CatalogPlugin, agent: Agent) -> String {
        let build = plugin.builds[agent.id] ?? plugin.name
        return """
            The \(plugin.name) plugin for \(agent.name) (\(build)) is not working right. Find out why and fix it, with
            the summon-mac skill's rules (inside the checkpoint; ask before deleting data, a memory database included).
            Start with: summon agents plugins \(agent.id), the agent's own logs, and the plugin's doctor command if it
            has one. Finish with what was wrong, what you changed, and how to check it now works.
            """
    }
}
