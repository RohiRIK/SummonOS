import Foundation

/// The panel's one undo action: the newest agent session from the last 12 hours that changed settings and is not
/// undone yet. Nil when there is nothing to undo, so the panel shows no row (actions and problems only).
public struct UndoOffer: Sendable, Equatable {
    public var checkpoint: String
    /// "Codex Session" for an agent, "Theme Tokyo Night" for a theme change.
    public var label: String
    public var changes: Int

    public var title: String { "Undo \(label) (\(changes) change\(changes == 1 ? "" : "s"))…" }

    public static func latest(_ sources: ActivitySources, now: Date = Date(), window: TimeInterval = 12 * 60 * 60) -> UndoOffer? {
        guard let checkpoint = sources.checkpoints.max(by: { $0.createdAt < $1.createdAt }),
              now.timeIntervalSince(checkpoint.createdAt) < window,
              !sources.log.contains(where: { $0.kind == EventKind.sessionUndo && $0.refs["checkpoint"] == checkpoint.id })
        else { return nil }
        // Undo snapshots, and changes one of them already rolled back, do not count.
        let undone = Set(sources.snapshots.compactMap(\.undoes))
        let changes = sources.snapshots
            .filter { $0.createdAt >= checkpoint.createdAt && $0.undoes == nil && !undone.contains($0.id) }
            .reduce(0) { $0 + $1.changes.count }
        guard changes > 0 else { return nil }
        let agent = sources.log.last { $0.refs["checkpoint"] == checkpoint.id && $0.refs["agent"] != nil }?.refs["agent"]
        // `summon agent` records the agent id ("claude"); MCP sessions record the name; themes record "Theme <name>".
        let label = agent.map { $0.hasPrefix("Theme ") ? $0 : (AgentRegistry.find($0)?.name ?? $0) + " Session" } ?? "Agent Session"
        return UndoOffer(checkpoint: checkpoint.id, label: label, changes: changes)
    }
}
