import Foundation

/// The tools `summon mcp` serves: this Mac's context, macctl settings (journaled, undoable), checkpoints and crash
/// reports. Kept to a handful so agents choose well; everything else is `summon commands --json` in a shell.
public enum SummonMCP {
    public struct Environment: Sendable {
        public var paths: SummonPaths
        public var runner: Runner
        public var tools: ToolLocator
        public var macctlPath: String?
        public var gitPath: String?
        public var version: String

        public init(paths: SummonPaths, runner: @escaping Runner, tools: ToolLocator, macctlPath: String?, gitPath: String?, version: String) {
            self.paths = paths
            self.runner = runner
            self.tools = tools
            self.macctlPath = macctlPath
            self.gitPath = gitPath
            self.version = version
        }
    }

    public static let instructions = """
        Summon gives you this Mac's live state and safe ways to change it. Call mac_context first to learn the \
        hardware, power, storage, network, displays, frontmost app and permissions. Change settings only with \
        settings_set: every change is snapshotted, settings_history lists them and settings_undo rolls them back. \
        Before a larger change, call checkpoint_create. Tell the user what you changed and how to undo it.
        """

    public static func server(_ env: Environment, session: MCPSession = MCPSession()) -> MCPServer {
        var server = MCPServer(name: "summon", version: env.version, instructions: instructions, tools: tools(env, session), resources: [
            MCPServer.Resource(uri: "mac://context", name: "This Mac", description: "summon context: a short snapshot of this Mac",
                               mimeType: "text/markdown") { await snapshot(env).render() },
        ])
        server.onInitialize = { params in await session.name(from: params) }
        return server
    }

    static func tools(_ env: Environment, _ session: MCPSession) -> [MCPServer.Tool] {
        let id: JSONValue = .object(["type": "string", "description": "Setting id from settings_list, for example dock.autohide"])
        return [
            MCPServer.Tool(name: "mac_context", title: "This Mac",
                           description: "Snapshot of this Mac: model, chip, RAM, macOS, power and thermal state, free space, network and VPN, displays, frontmost app and window, running apps, appearance, permissions, installed agents, recent crashes.",
                           inputSchema: schema(["sections": .object([
                               "type": "array", "items": .object(["type": "string", "enum": .array(MacContext.sections.map(JSONValue.string))]),
                               "description": "Only these sections; all when omitted"])]),
                           readOnly: true) { arguments in
                let sections = arguments["sections"]?.array?.compactMap(\.string)
                let context = await snapshot(env)
                guard let sections else { return MCPServer.ToolResult(text: context.render(), structured: try? .encoding(context)) }
                do {
                    let trimmed = try context.only(sections)
                    return MCPServer.ToolResult(text: trimmed.render(), structured: try? .encoding(trimmed))
                } catch {
                    return .error(String(describing: error))
                }
            },
            MCPServer.Tool(name: "settings_list", title: "List Mac settings",
                           description: "Every setting macctl can read and change, with its id, type, risk and current value.",
                           inputSchema: schema([:]), readOnly: true) { _ in
                await macctl(env, ["list"])
            },
            MCPServer.Tool(name: "settings_describe", title: "Describe a setting",
                           description: "Full schema of one setting: type, allowed values, risk, permissions, side effects and what undo restores.",
                           inputSchema: schema(["id": id], required: ["id"]), readOnly: true) { arguments in
                guard let setting = settingID(arguments["id"]) else { return invalidID }
                return await macctl(env, ["describe", "--", setting])
            },
            MCPServer.Tool(name: "settings_get", title: "Read settings",
                           description: "Current values of one or more settings.",
                           inputSchema: schema(["ids": .object(["type": "array", "items": id, "minItems": 1])], required: ["ids"]),
                           readOnly: true) { arguments in
                let ids = arguments["ids"]?.array?.map(settingID) ?? []
                guard !ids.isEmpty, !ids.contains(nil) else { return invalidID }
                return await macctl(env, ["get", "--"] + ids.compactMap { $0 })
            },
            MCPServer.Tool(name: "settings_set", title: "Change a setting",
                           description: "Change one setting. A snapshot is saved first, so settings_undo can roll it back. Risky settings need confirm: true after the user agrees; dry_run shows the change without making it.",
                           inputSchema: schema([
                               "id": id,
                               "value": .object(["description": "New value: true/false, a number, an enum name or a path"]),
                               "confirm": .object(["type": "boolean", "description": "The user agreed to a change that needs confirmation"]),
                               "dry_run": .object(["type": "boolean"]),
                           ], required: ["id", "value"]),
                           readOnly: false) { arguments in
                guard let setting = settingID(arguments["id"]) else { return invalidID }
                guard let value = plainValue(arguments["value"]) else { return .error("value must be a string, number or boolean") }
                var command = ["set"]
                let dryRun = arguments["dry_run"]?.bool == true
                if dryRun { command.append("--dry-run") }
                if arguments["confirm"]?.bool == true { command.append("--yes") }
                guard !dryRun else { return await macctl(env, command + ["--", setting, value]) }
                // The first real change of a session gets a checkpoint, so one undo covers the whole session.
                let checkpoint = await session.checkpoint(env)
                var result = await macctl(env, command + ["--", setting, value])
                if !result.isError {
                    result.text += "\nUndo everything this session changed: summon checkpoint undo \(checkpoint.id)"
                }
                return result
            },
            MCPServer.Tool(name: "settings_undo", title: "Undo a settings change",
                           description: "Roll back a change from settings_history (the newest when id is omitted). Keys the user changed by hand since are left alone and reported. dry_run shows what would be restored.",
                           inputSchema: schema(["id": .object(["type": "string", "description": "Snapshot id from settings_history"]),
                                                "dry_run": .object(["type": "boolean"])]),
                           readOnly: false) { arguments in
                var command = ["undo"]
                if arguments["dry_run"]?.bool == true { command.append("--dry-run") }
                if let snapshot = arguments["id"] {
                    guard let snapshot = settingID(snapshot) else { return .error("id must be a snapshot id from settings_history") }
                    command += ["--", snapshot]
                }
                return await macctl(env, command)
            },
            MCPServer.Tool(name: "settings_history", title: "Settings changes",
                           description: "Snapshots saved before each settings change, newest first: what changed and when.",
                           inputSchema: schema([:]), readOnly: true) { _ in
                await macctl(env, ["snapshot", "list"])
            },
            MCPServer.Tool(name: "checkpoint_list", title: "Checkpoints",
                           description: "Checkpoints Summon took before agent sessions: ~/.config commit and macctl marker. Undo one with `summon checkpoint undo <id>`.",
                           inputSchema: schema([:]), readOnly: true) { _ in
                do {
                    let all = try service(env).listValidated()
                    let lines = all.reversed().map { "\($0.id)  \($0.label)  \(ISO8601DateFormatter().string(from: $0.createdAt))" }
                    return MCPServer.ToolResult(text: lines.isEmpty ? "No checkpoints yet." : lines.joined(separator: "\n"),
                                                structured: try? .encoding(["checkpoints": all]))
                } catch {
                    return .error(String(describing: error))
                }
            },
            MCPServer.Tool(name: "checkpoint_create", title: "Take a checkpoint",
                           description: "Save a restore point (commit ~/.config, mark macctl) before a larger change.",
                           inputSchema: schema(["label": .object(["type": "string"])]), readOnly: false) { arguments in
                let label = arguments["label"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
                let (checkpoint, problems) = await service(env).create(label: label?.isEmpty == false ? label! : "mcp")
                let text = "Checkpoint \(checkpoint.id) \"\(checkpoint.label)\". Undo: summon checkpoint undo \(checkpoint.id)"
                return MCPServer.ToolResult(text: ([text] + problems).joined(separator: "\n"), structured: try? .encoding(checkpoint))
            },
            MCPServer.Tool(name: "crash_list", title: "Crash reports",
                           description: "Recent crash, hang and panic reports on this Mac, newest first (programs the user muted are skipped).",
                           inputSchema: schema(["limit": .object(["type": "integer", "minimum": 1, "maximum": 50])]),
                           readOnly: true) { arguments in
                let limit = min(max(arguments["limit"]?.int ?? 10, 1), 50)
                let reports = CrashWatcher(paths: env.paths).reports(since: nil, limit: limit)
                let lines = reports.map { report in
                    "\(report.timestamp ?? "unknown time")  \(report.kind.rawValue)  \(report.program)  \(report.file)"
                }
                return MCPServer.ToolResult(text: lines.isEmpty ? "No crash, hang or panic reports." : lines.joined(separator: "\n"),
                                            structured: try? .encoding(["reports": reports]))
            },
        ]
    }

    /// A readable agent name from MCP `clientInfo.name` ("claude-code", "codex-mcp-client", "cursor-vscode", ...).
    public static func agentName(_ client: String?) -> String {
        guard let client, !client.isEmpty else { return "An agent" }
        let key = client.lowercased()
        let known: [(String, String)] = [("claude", "Claude Code"), ("codex", "Codex"), ("cursor", "Cursor"),
                                         ("opencode", "OpenCode"), ("hermes", "Hermes"), ("openclaw", "OpenClaw"),
                                         ("antigravity", "Antigravity CLI"), ("agy", "Antigravity CLI"), ("raycast", "Raycast")]
        if let match = known.first(where: { key.contains($0.0) }) { return match.1 }
        return key == "pi" || key.hasPrefix("pi-") ? "Pi" : client
    }

    static func snapshot(_ env: Environment) async -> MacContext {
        let hidden = AgentSettingsStore(paths: env.paths).load().hiddenContext
        return await MainActor.run { MacContextProbe.live(paths: env.paths, tools: env.tools, hidden: hidden) }
    }

    static func service(_ env: Environment) -> CheckpointService {
        CheckpointService(paths: env.paths, runner: env.runner, gitPath: env.gitPath, macctlPath: env.macctlPath)
    }

    /// Runs macctl with `--json` and passes its JSON through; exit 3 and 2 get a next step for the agent.
    static func macctl(_ env: Environment, _ arguments: [String]) async -> MCPServer.ToolResult {
        guard let path = env.macctlPath else {
            return .error("macctl is not installed, so settings cannot be read or changed. Install SummonOS with install.sh.")
        }
        // --json goes before `--`, which ends the options.
        var command = arguments
        command.insert("--json", at: command.firstIndex(of: "--") ?? command.endIndex)
        do {
            return output(try await env.runner(path, command), isError: false)
        } catch let RunnerError.failed(_, status, text) {
            var result = output(text, isError: true)
            if status == 3 { result.text += "\nThis change needs the user's confirmation. Ask them, then call again with confirm: true." }
            if status == 2 { result.text += "\nmacctl needs a permission; `macctl doctor` says which and how to grant it." }
            return result
        } catch {
            return .error(String(describing: error))
        }
    }

    static func output(_ text: String, isError: Bool) -> MCPServer.ToolResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8))
        if case .object = json { return MCPServer.ToolResult(text: trimmed, structured: json, isError: isError) }
        return MCPServer.ToolResult(text: trimmed, isError: isError)
    }

    static let invalidID = MCPServer.ToolResult.error("ids must look like dock.autohide (letters, digits, dots, dashes); see settings_list")

    /// Ids go to macctl as arguments, so only plain ids pass (no option-looking strings).
    static func settingID(_ value: JSONValue?) -> String? {
        guard let text = value?.string, let first = text.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first),
              text.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || ".-_:".unicodeScalars.contains($0) }) else { return nil }
        return text
    }

    static func plainValue(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text): text
        case .bool(let flag): flag ? "true" : "false"
        case .int(let number): String(number)
        case .double(let number): String(number)
        default: nil
        }
    }

    static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var body: [String: JSONValue] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { body["required"] = .array(required.map(JSONValue.string)) }
        return .object(body)
    }
}

/// One MCP connection: which agent it is, and the checkpoint taken before its first change. Its changes then show
/// in Activity as that agent's session, and `summon checkpoint undo <id>` (or the panel) undoes all of them.
public actor MCPSession {
    public private(set) var agent = "An agent"
    public private(set) var taken: Checkpoint?
    let id = UUID().uuidString

    public init() {}

    func name(from params: JSONValue) {
        agent = SummonMCP.agentName(params["clientInfo"]?["name"]?.string)
    }

    func checkpoint(_ env: SummonMCP.Environment) async -> Checkpoint {
        if let taken { return taken }
        let (checkpoint, _) = await SummonMCP.service(env).create(label: "\(agent) via MCP")
        taken = checkpoint
        try? EventLog(paths: env.paths).append(LoggedEvent(
            kind: EventKind.sessionStart, title: "\(agent) session started (MCP)",
            refs: ["session": id, "checkpoint": checkpoint.id, "agent": agent]))
        return checkpoint
    }

    /// Called when the client closes the connection; nothing is logged for a session that changed nothing.
    public func end(_ env: SummonMCP.Environment) {
        guard let taken else { return }
        try? EventLog(paths: env.paths).append(LoggedEvent(
            kind: EventKind.sessionEnd, title: "\(agent) session ended (MCP)",
            refs: ["session": id, "checkpoint": taken.id, "agent": agent]))
    }
}
