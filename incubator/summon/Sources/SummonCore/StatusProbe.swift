import Foundation

/// The status strip at the top of the Activity window, and `summon status`.
public struct SummonStatus: Sendable, Equatable, Encodable {
    public struct AgentState: Sendable, Equatable, Encodable {
        public var name: String?
        public var installed: Bool
        /// A session started (plugin hook) and has not ended.
        public var running: Bool
        public var since: Date?
        public var folder: String?
    }

    public struct MacctlState: Sendable, Equatable, Encodable {
        public var installed: Bool
        /// Failed `macctl doctor` checks, as `name: detail`.
        public var problems: [String]
    }

    public var agent: AgentState
    public var macctl: MacctlState
    public var lastChange: ActivityEvent?
    public var lastCheckpoint: Checkpoint?
    /// Undo can only put `~/.config` files back when it is a git repo.
    public var configIsRepo: Bool
    /// Crash, hang and panic reports in the last 24 hours (muted programs skipped).
    public var recentProblems: Int
    /// Plain sentences for whatever needs the person's attention.
    public var warnings: [String]
}

public enum StatusProbe {
    /// A session start older than this with no end is treated as ended (the terminal was closed hard).
    public static let staleSession: TimeInterval = 12 * 60 * 60

    public static func build(
        agent: Agent?,
        agentInstalled: Bool,
        log: [LoggedEvent],
        macctlInstalled: Bool,
        macctlProblems: [String],
        snapshots: [MacctlSnapshot],
        checkpoints: [Checkpoint],
        configIsRepo: Bool,
        crashes: [CrashReport],
        crashDates: [String: Date] = [:],
        now: Date = Date()
    ) -> SummonStatus {
        let session = openSession(in: log, now: now)
        let agentState = SummonStatus.AgentState(
            name: agent?.name,
            installed: agentInstalled,
            running: session != nil,
            since: session?.time,
            folder: session?.refs["folder"]
        )
        let lastChange = snapshots.first { !$0.changes.isEmpty }.map { ActivityFeed.event(from: $0) }
        let dayAgo = now.addingTimeInterval(-24 * 60 * 60)
        let recent = crashes.filter { report in
            guard let date = crashDates[report.file] ?? ActivityFeed.crashDate(report) else { return false }
            return date >= dayAgo
        }.count

        var warnings: [String] = []
        if agent == nil {
            warnings.append("No default agent. Choose one with: summon default agent claude")
        } else if !agentInstalled, let agent {
            warnings.append("\(agent.name) is not installed. Install it with: \(agent.installHint)")
        }
        if !macctlInstalled {
            warnings.append("macctl is not installed, so settings changes are not recorded or undoable.")
        }
        warnings.append(contentsOf: macctlProblems.map { "macctl: \($0)" })
        if !configIsRepo {
            warnings.append("~/.config is not a git repo, so undo cannot put changed files back. Fix: git -C ~/.config init")
        }
        if recent > 0 {
            warnings.append(recent == 1 ? "1 crash or hang in the last day." : "\(recent) crashes or hangs in the last day.")
        }

        return SummonStatus(
            agent: agentState,
            macctl: SummonStatus.MacctlState(installed: macctlInstalled, problems: macctlProblems),
            lastChange: lastChange,
            lastCheckpoint: checkpoints.max { $0.createdAt < $1.createdAt },
            configIsRepo: configIsRepo,
            recentProblems: recent,
            warnings: warnings
        )
    }

    /// The newest `session.start` with no later `session.end` for the same session id
    /// (or, without ids, no later end at all), started less than `staleSession` ago.
    public static func openSession(in log: [LoggedEvent], now: Date = Date()) -> LoggedEvent? {
        let ordered = log.sorted { $0.time < $1.time }
        guard let start = ordered.last(where: { $0.kind == EventKind.sessionStart }) else { return nil }
        guard now.timeIntervalSince(start.time) < staleSession else { return nil }
        let ended = ordered.contains { entry in
            guard entry.kind == EventKind.sessionEnd, entry.time >= start.time else { return false }
            guard let id = start.refs["session"], let endID = entry.refs["session"] else { return true }
            return id == endID
        }
        return ended ? nil : start
    }

    /// Failed checks from `macctl doctor --json`: `{"ok": true, "result": {"checks": [{name, ok, detail}]}}`.
    public static func doctorProblems(fromJSON output: String) -> [String] {
        struct Envelope: Decodable {
            struct Report: Decodable {
                struct Check: Decodable {
                    var name: String
                    var ok: Bool
                    var detail: String
                }
                var checks: [Check]
            }
            var ok: Bool
            var result: Report?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(output.utf8)) else {
            return ["doctor output could not be read"]
        }
        guard envelope.ok, let report = envelope.result else { return ["doctor failed"] }
        return report.checks.filter { !$0.ok }.map { "\($0.name): \($0.detail)" }
    }
}
