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

    public func argv(prompt: String?) -> [String] {
        guard let prompt, !prompt.isEmpty else { return interactive }
        return withPrompt + [prompt]
    }
}

public enum AgentRegistry {
    public static let all: [Agent] = [
        Agent(
            id: "claude", name: "Claude Code", command: "claude", aliases: ["claude-code"],
            interactive: ["claude", "--permission-mode", "auto"],
            withPrompt: ["claude", "--permission-mode", "auto", "--"],
            installHint: "brew install --cask claude-code"
        ),
        Agent(
            id: "codex", name: "Codex", command: "codex", aliases: ["openai-codex"],
            interactive: ["codex", "--approve-for-me"],
            withPrompt: ["codex", "--approve-for-me", "--"],
            installHint: "brew install codex"
        ),
        Agent(
            id: "opencode", name: "OpenCode", command: "opencode", aliases: ["open-code"],
            interactive: ["opencode", "--auto"],
            withPrompt: ["opencode", "--auto", "--prompt"],
            installHint: "brew install sst/tap/opencode"
        ),
        Agent(
            id: "copilot", name: "GitHub Copilot", command: "copilot", aliases: ["github-copilot"],
            interactive: ["copilot", "--allow-all"],
            withPrompt: ["copilot", "--allow-all", "--interactive"],
            installHint: "npm install -g @github/copilot"
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
            installHint: "npm install -g antigravity-cli"
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
