import Foundation

/// One coding-agent CLI Summon can launch. Mirrors Omarchy's `omarchy-agent` table:
/// every launch uses the agent's own "don't stop to ask" mode, because a summoned agent runs unattended
/// behind a checkpoint (see `Checkpoint`).
public struct Agent: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    /// Binary name looked up on PATH.
    public let command: String
    public let aliases: [String]
    /// Full argv for an interactive session without a prompt.
    public let interactive: [String]
    /// argv prefix for a session seeded with a prompt; the prompt is appended as the last argument.
    public let withPrompt: [String]
    /// Shown when the binary is missing.
    public let installHint: String
    /// The CLI's model option (verified per CLI); nil when the interactive CLI has none.
    public var modelFlag: String? = nil
    /// The agent's own skill folder, relative to home; nil when unknown (it gets skill paths in the prompt instead).
    public var skillFolder: String? = nil
    /// argv prefix for a scheduled task: the CLI prints its answer and exits, under its own permission rules
    /// (no bypass flag), so a run nobody watches can read and report but not change things. The prompt is
    /// appended last. nil when the CLI has no verified mode like that, so tasks cannot use it.
    public var headless: [String]? = nil

    public func argv(prompt: String?) -> [String] {
        guard let prompt, !prompt.isEmpty else { return interactive }
        return withPrompt + [prompt]
    }

    /// `argv(prompt:)` with the model option right after the command, when the CLI has one.
    public func argv(prompt: String?, model: String?) -> [String] {
        let base = argv(prompt: prompt)
        guard let modelFlag, let model = model?.trimmingCharacters(in: .whitespaces), !model.isEmpty else { return base }
        return [base[0], modelFlag, model] + base.dropFirst()
    }

    /// The task argv for `prompt`, with the model option before a trailing `--`; nil without a headless mode.
    public func headlessArgv(prompt: String, model: String?) -> [String]? {
        guard var base = headless else { return nil }
        if let modelFlag, let model = model?.trimmingCharacters(in: .whitespaces), !model.isEmpty {
            base.insert(contentsOf: [modelFlag, model], at: base.last == "--" ? base.count - 1 : base.count)
        }
        return base + [prompt]
    }
}

public enum AgentRegistry {
    public static let all: [Agent] = [
        Agent(
            id: "claude", name: "Claude Code", command: "claude", aliases: ["claude-code"],
            interactive: ["claude", "--dangerously-skip-permissions"],
            withPrompt: ["claude", "--dangerously-skip-permissions", "--"],
            installHint: "brew install --cask claude-code", modelFlag: "--model", skillFolder: ".claude/skills",
            headless: ["claude", "--print", "--"]
        ),
        Agent(
            id: "codex", name: "Codex", command: "codex", aliases: ["openai-codex"],
            interactive: ["codex", "--dangerously-bypass-approvals-and-sandbox"],
            withPrompt: ["codex", "--dangerously-bypass-approvals-and-sandbox", "--"],
            installHint: "brew install codex", modelFlag: "--model", skillFolder: ".codex/skills",
            headless: ["codex", "exec", "--sandbox", "read-only", "--"]
        ),
        Agent(
            id: "opencode", name: "OpenCode", command: "opencode", aliases: ["open-code"],
            interactive: ["opencode", "--auto"],
            withPrompt: ["opencode", "--auto", "--prompt"],
            installHint: "brew install sst/tap/opencode", skillFolder: ".config/opencode/skills"
        ),
        Agent(
            id: "copilot", name: "GitHub Copilot", command: "copilot", aliases: ["github-copilot"],
            interactive: ["copilot", "--allow-all"],
            withPrompt: ["copilot", "--allow-all", "--interactive"],
            installHint: "npm install -g @github/copilot",
            headless: ["copilot", "--no-ask-user", "-s", "-p"]
        ),
        Agent(
            // A one-word prompt naming a subcommand would run that subcommand, so `agent --` is spelled out.
            id: "cursor-agent", name: "Cursor CLI", command: "cursor-agent", aliases: ["cursor"],
            interactive: ["cursor-agent", "--yolo", "--trust"],
            withPrompt: ["cursor-agent", "--yolo", "--trust", "agent", "--"],
            installHint: "curl https://cursor.com/install -fsS | bash"
        ),
        Agent(
            id: "agy", name: "Antigravity", command: "agy", aliases: ["antigravity", "gemini", "gemini-cli"],
            interactive: ["agy", "--dangerously-skip-permissions"],
            withPrompt: ["agy", "--dangerously-skip-permissions", "--prompt-interactive"],
            installHint: "npm install -g antigravity-cli", modelFlag: "--model", skillFolder: ".gemini/config/skills"
        ),
        Agent(
            // Pi has no permission prompts: it runs its tools without asking, so there is no bypass flag.
            id: "pi", name: "Pi", command: "pi", aliases: ["pi-agent", "pi-coding-agent"],
            interactive: ["pi"],
            withPrompt: ["pi", "--"],
            installHint: "bun add -g @earendil-works/pi-coding-agent", modelFlag: "--model", skillFolder: ".pi/agent/skills"
        ),
        Agent(
            id: "grok", name: "Grok", command: "grok", aliases: ["grok-build"],
            interactive: ["grok", "--permission-mode", "bypassPermissions"],
            withPrompt: ["grok", "--permission-mode", "bypassPermissions", "--"],
            installHint: "npm install -g @xai/grok"
        ),
    ]

    public static func find(_ name: String) -> Agent? {
        let key = name.lowercased()
        return all.first { $0.id == key || $0.aliases.contains(key) }
    }
}

/// `~/.config/summon/defaults/agent`. Nothing is preselected: Summon picks no agent for you.
public struct DefaultAgentStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    public func load() -> Agent? {
        guard let id = TextFile.firstLine(paths.defaultAgentFile) else { return nil }
        return AgentRegistry.find(id)
    }

    public func save(_ agent: Agent) throws {
        try TextFile.write(agent.id + "\n", to: paths.defaultAgentFile)
    }
}
