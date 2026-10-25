import Foundation

/// How `summon connect` reaches one agent: register the `summon mcp` server in its config and add a marked
/// block to its always-loaded instructions file. Paths and commands are from each agent's docs (2026-10-25);
/// see docs/research/2026-10-25-agent-mcp-configs.md.
public struct ConnectTarget: Sendable, Equatable {
    public enum Method: Sendable, Equatable {
        /// The agent's own CLI; `{summon}` is replaced by summon's path. `remove` nil: the CLI has no remove.
        case cli(add: [String], remove: [String]?, check: [String]?)
        /// A plain JSON file with a top-level `mcpServers` map, relative to home.
        case jsonFile(String)
    }

    public var id: String
    public var name: String
    /// Binary on PATH; the agent counts as present when it exists.
    public var command: String?
    /// Also present when one of these exists (home-relative, or absolute for apps).
    public var markers: [String]
    public var method: Method
    /// Markdown file loaded into every session, home-relative; nil when the agent has none Summon should touch.
    public var instructions: String?

    public static let all: [ConnectTarget] = [
        ConnectTarget(id: "claude", name: "Claude Code", command: "claude", markers: [],
                      method: .cli(add: ["mcp", "add", "--scope", "user", "summon", "--", "{summon}", "mcp"],
                                   remove: ["mcp", "remove", "--scope", "user", "summon"], check: ["mcp", "get", "summon"]),
                      instructions: ".claude/CLAUDE.md"),
        ConnectTarget(id: "codex", name: "Codex", command: "codex", markers: [],
                      method: .cli(add: ["mcp", "add", "summon", "--", "{summon}", "mcp"],
                                   remove: ["mcp", "remove", "summon"], check: ["mcp", "get", "summon"]),
                      instructions: ".codex/AGENTS.md"),
        ConnectTarget(id: "cursor", name: "Cursor", command: "cursor-agent", markers: [".cursor", "/Applications/Cursor.app"],
                      method: .jsonFile(".cursor/mcp.json"), instructions: nil),
        ConnectTarget(id: "opencode", name: "OpenCode", command: "opencode", markers: [],
                      method: .cli(add: ["mcp", "add", "--global", "summon", "--", "{summon}", "mcp"], remove: nil, check: nil),
                      instructions: ".config/opencode/AGENTS.md"),
        // SOUL.md is Hermes's identity, not an instructions file, so it gets no block; the server's
        // MCP instructions carry the same advice.
        ConnectTarget(id: "hermes", name: "Hermes", command: "hermes", markers: [],
                      method: .cli(add: ["mcp", "add", "summon", "--command", "{summon}", "--args", "mcp"],
                                   remove: ["mcp", "remove", "summon"], check: nil),
                      instructions: nil),
        ConnectTarget(id: "openclaw", name: "OpenClaw", command: "openclaw", markers: [],
                      method: .cli(add: ["mcp", "add", "summon", "--command", "{summon}", "--arg", "mcp"],
                                   remove: ["mcp", "remove", "summon"], check: nil),
                      instructions: ".openclaw/workspace/AGENTS.md"),
        ConnectTarget(id: "agy", name: "Antigravity CLI", command: "agy", markers: [],
                      method: .jsonFile(".gemini/config/mcp_config.json"), instructions: ".gemini/GEMINI.md"),
        ConnectTarget(id: "pi", name: "Pi", command: "pi", markers: [".pi/agent"],
                      method: .jsonFile(".pi/agent/mcp.json"), instructions: ".pi/agent/AGENTS.md"),
    ]

    public static func find(_ name: String) -> ConnectTarget? {
        let key = name.lowercased()
        // Registry names and aliases work too ("gemini" is agy, "cursor-agent" is Cursor).
        return all.first { $0.id == key } ?? AgentRegistry.find(key).flatMap { agent in all.first { $0.command == agent.command } }
    }
}

public struct ConnectResult: Sendable, Equatable, Encodable {
    public enum Status: String, Sendable, Encodable {
        case connected, alreadyConnected = "already-connected", disconnected, notInstalled = "not-installed", failed, manual
    }

    public var id: String
    public var name: String
    public var status: Status
    public var detail: String
    /// Files Summon wrote (backups are in `~/.local/state/summon/backups/connect/`).
    public var files: [String]
}

public struct AgentConnector: Sendable {
    public let paths: SummonPaths
    public let runner: Runner
    public let tools: ToolLocator
    public let summonPath: String
    public let fileExists: @Sendable (String) -> Bool

    public init(paths: SummonPaths, runner: @escaping Runner, tools: ToolLocator, summonPath: String,
                fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.paths = paths
        self.runner = runner
        self.tools = tools
        self.summonPath = summonPath
        self.fileExists = fileExists
    }

    public static let blockStart = "<!-- summon:begin (added by `summon connect`; `summon disconnect` removes it) -->"
    public static let blockEnd = "<!-- summon:end -->"
    public static let block = """
        \(blockStart)
        ## This Mac (Summon)
        - Before Mac-specific work, run `summon context` (or the `summon` MCP tool `mac_context`): hardware, power, \
        storage, network, displays, frontmost app and permissions.
        - Change macOS settings only through `macctl` or the MCP tool `settings_set`: each change is snapshotted and \
        `macctl undo` rolls it back.
        - `summon commands --json` lists everything else Summon can do.
        \(blockEnd)
        """

    public func isPresent(_ target: ConnectTarget) -> Bool {
        if let command = target.command, tools.find(command) != nil { return true }
        return target.markers.contains { fileExists($0.hasPrefix("/") ? $0 : url($0).path) }
    }

    public func connect(_ targets: [ConnectTarget], dryRun: Bool, now: Date = Date()) async -> [ConnectResult] {
        var results: [ConnectResult] = []
        for target in targets {
            guard isPresent(target) else {
                results.append(result(target, .notInstalled, "\(target.name) is not installed"))
                continue
            }
            var outcome = await registerServer(target, dryRun: dryRun, now: now)
            if outcome.status != .failed, let file = target.instructions {
                do {
                    if try writeBlock(file, remove: false, dryRun: dryRun, now: now) { outcome.files.append("~/" + file) }
                } catch {
                    outcome = result(target, .failed, "instructions ~/\(file): \(error)", files: outcome.files)
                }
            }
            if outcome.status == .alreadyConnected, !outcome.files.isEmpty { outcome.status = .connected }
            results.append(outcome)
        }
        return results
    }

    public func disconnect(_ targets: [ConnectTarget], dryRun: Bool, now: Date = Date()) async -> [ConnectResult] {
        var results: [ConnectResult] = []
        for target in targets {
            var files: [String] = []
            var notes: [String] = []
            var status = ConnectResult.Status.disconnected
            switch target.method {
            case let .cli(_, remove, _):
                guard let command = target.command, let binary = tools.find(command) else {
                    notes.append("\(target.name) is not installed; nothing to remove from its config")
                    break
                }
                guard let remove else {
                    status = .manual
                    notes.append("\(target.name) has no remove command: delete `summon` from its MCP config by hand")
                    break
                }
                if dryRun {
                    notes.append("would run: \(([command] + remove).joined(separator: " "))")
                } else if (try? await runner(binary, remove)) == nil {
                    notes.append("\(command) found no `summon` server to remove")
                }
            case let .jsonFile(file):
                do {
                    if try editJSON(file, dryRun: dryRun, now: now, change: { servers in servers.removeValue(forKey: "summon") != nil }) {
                        files.append("~/" + file)
                    }
                } catch {
                    status = .failed
                    notes.append("~/\(file): \(error)")
                }
            }
            if let file = target.instructions {
                do {
                    if try writeBlock(file, remove: true, dryRun: dryRun, now: now) { files.append("~/" + file) }
                } catch {
                    status = .failed
                    notes.append("instructions ~/\(file): \(error)")
                }
            }
            results.append(result(target, status, notes.joined(separator: "; "), files: files))
        }
        return results
    }

    func registerServer(_ target: ConnectTarget, dryRun: Bool, now: Date) async -> ConnectResult {
        switch target.method {
        case let .cli(add, _, check):
            guard let command = target.command, let binary = tools.find(command) else {
                return result(target, .notInstalled, "the `\(target.command ?? target.id)` command is not on PATH")
            }
            if let check, (try? await runner(binary, check)) != nil {
                return result(target, .alreadyConnected, "summon is already in its MCP servers")
            }
            let arguments = add.map { $0 == "{summon}" ? summonPath : $0 }
            if dryRun { return result(target, .connected, "would run: \(([command] + arguments).joined(separator: " "))") }
            do {
                _ = try await runner(binary, arguments)
                return result(target, .connected, "added with `\(command) \(add.prefix(2).joined(separator: " "))`")
            } catch {
                return result(target, .failed, String(describing: error))
            }
        case let .jsonFile(file):
            do {
                let server: [String: Any] = ["command": summonPath, "args": ["mcp"]]
                let changed = try editJSON(file, dryRun: dryRun, now: now) { servers in
                    if let current = servers["summon"] as? [String: Any], NSDictionary(dictionary: current).isEqual(to: server) {
                        return false
                    }
                    servers["summon"] = server
                    return true
                }
                return changed
                    ? result(target, .connected, (dryRun ? "would add" : "added") + " summon to ~/\(file)", files: ["~/" + file])
                    : result(target, .alreadyConnected, "summon is already in ~/\(file)")
            } catch {
                return result(target, .failed, "~/\(file): \(error)")
            }
        }
    }

    /// Changes the `mcpServers` map of a JSON file, keeping every other key. A file that is not a JSON object
    /// is left alone (never overwritten). Returns whether anything changed.
    func editJSON(_ file: String, dryRun: Bool, now: Date, change: (inout [String: Any]) -> Bool) throws -> Bool {
        let target = url(file)
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: target), !data.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConnectError.notAnObject
            }
            root = object
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        guard change(&servers) else { return false }
        root["mcpServers"] = servers
        if dryRun { return true }
        try backup(target, now: now)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try TextFile.write(String(decoding: data, as: UTF8.self) + "\n", to: target)
        return true
    }

    /// Adds, refreshes or removes the marked block; text outside the markers is never touched.
    func writeBlock(_ file: String, remove: Bool, dryRun: Bool, now: Date) throws -> Bool {
        let target = url(file)
        let current = TextFile.read(target) ?? ""
        let updated = Self.replacingBlock(in: current, with: remove ? nil : Self.block)
        guard updated != current else { return false }
        if dryRun { return true }
        try backup(target, now: now)
        try TextFile.write(updated, to: target)
        return true
    }

    static func replacingBlock(in text: String, with block: String?) -> String {
        guard let start = text.range(of: blockStart),
              let end = text.range(of: blockEnd, range: start.upperBound..<text.endIndex) else {
            guard let block else { return text }
            if text.isEmpty { return block + "\n" }
            return text + (text.hasSuffix("\n") ? "\n" : "\n\n") + block + "\n"
        }
        // An existing block is replaced where it is, so running connect again changes nothing.
        if let block { return String(text[..<start.lowerBound]) + block + String(text[end.upperBound...]) }
        var before = String(text[..<start.lowerBound])
        var after = String(text[end.upperBound...])
        if after.hasPrefix("\n") { after.removeFirst() }
        // Leave no trailing blank lines behind when the block was at the end.
        if after.isEmpty { while before.hasSuffix("\n\n") { before.removeLast() } }
        let result = before + after
        return result == "\n" ? "" : result
    }

    func backup(_ file: URL, now: Date) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "")
        let relative = file.path.replacingOccurrences(of: paths.home.resolvingSymlinksInPath().path + "/", with: "")
        let copy = paths.state.appendingPathComponent("backups/connect/\(stamp)/\(relative)")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.copyItem(at: file, to: copy) }
    }

    /// Symlinks are followed, so a dotfiles-managed CLAUDE.md or mcp.json is edited in place, not replaced.
    func url(_ relative: String) -> URL { paths.home.appendingPathComponent(relative).resolvingSymlinksInPath() }

    func result(_ target: ConnectTarget, _ status: ConnectResult.Status, _ detail: String, files: [String] = []) -> ConnectResult {
        ConnectResult(id: target.id, name: target.name, status: status, detail: detail, files: files)
    }
}

public enum ConnectError: Error, CustomStringConvertible {
    case notAnObject

    public var description: String { "not a JSON object; left unchanged (fix or remove it, then connect again)" }
}
