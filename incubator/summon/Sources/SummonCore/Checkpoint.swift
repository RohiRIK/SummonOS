import Foundation

/// Taken before every summoned agent session so `summon checkpoint undo` can put things back:
/// a marker in macctl's snapshot history (macctl snapshots on every change, so undo reverts every
/// snapshot after the marker), and a git commit of `~/.config` when it is a repo.
/// Recorded in `~/.config/summon/checkpoints.json`, newest last.
public struct Checkpoint: Sendable, Equatable, Codable, Identifiable {
    /// `yyyyMMdd-HHmmss`, unique enough for a person taking checkpoints by hand.
    public var id: String
    public var label: String
    public var createdAt: Date
    /// Commit hash in `~/.config`, when it is a git repo.
    public var configCommit: String?
    /// Newest macctl snapshot id when the checkpoint was taken, `"none"` when macctl had none yet,
    /// nil when macctl was not available. Undo reverts every macctl snapshot newer than this.
    public var macctlSnapshot: String?

    public init(id: String, label: String, createdAt: Date, configCommit: String?, macctlSnapshot: String?) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
        self.configCommit = configCommit
        self.macctlSnapshot = macctlSnapshot
    }

    public static func makeID(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

public struct CheckpointService: Sendable {
    public let paths: SummonPaths
    public let runner: Runner
    public let gitPath: String?
    public let macctlPath: String?

    public init(paths: SummonPaths, runner: @escaping Runner, gitPath: String?, macctlPath: String?) {
        self.paths = paths
        self.runner = runner
        self.gitPath = gitPath
        self.macctlPath = macctlPath
    }

    public var storeFile: URL { paths.config.appendingPathComponent("checkpoints.json") }

    public var configIsRepo: Bool {
        FileManager.default.fileExists(atPath: paths.userConfig.appendingPathComponent(".git").path)
    }

    /// The commands `create` runs, in order. Exposed for tests and for `--dry-run`.
    public func createSteps(label: String) -> [LaunchPlan] {
        var steps: [LaunchPlan] = []
        if let macctlPath {
            steps.append(LaunchPlan(executable: macctlPath, arguments: ["snapshot", "list", "--json"]))
        }
        if let gitPath, configIsRepo {
            let dir = paths.userConfig.path
            steps.append(LaunchPlan(executable: gitPath, arguments: ["-C", dir, "add", "-A"]))
            steps.append(LaunchPlan(executable: gitPath, arguments: ["-C", dir, "commit", "-q", "--allow-empty", "-m", "summon checkpoint: \(label)"]))
        }
        return steps
    }

    /// Best effort: a failing step is reported but never blocks the agent from starting.
    public func create(label: String, now: Date = Date()) async -> (Checkpoint, [String]) {
        var problems: [String] = []
        var snapshot: String?
        for step in createSteps(label: label) {
            do {
                let output = try await runner(step.executable, step.arguments)
                if step.executable == macctlPath {
                    let snapshots = try Self.snapshots(fromListJSON: output)
                    snapshot = snapshots.first?.id ?? Self.noSnapshots
                }
            } catch {
                problems.append(String(describing: error))
            }
        }
        var commit: String?
        if let gitPath, configIsRepo {
            if let head = try? await runner(gitPath, ["-C", paths.userConfig.path, "rev-parse", "HEAD"]) {
                commit = head.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let checkpoint = Checkpoint(id: Checkpoint.makeID(now), label: label, createdAt: now, configCommit: commit, macctlSnapshot: snapshot)
        do {
            var all = list()
            all.append(checkpoint)
            try save(Array(all.suffix(100)))
        } catch {
            problems.append("could not record checkpoint: \(error)")
        }
        return (checkpoint, problems)
    }

    /// Marker for "macctl had no snapshots yet", so undo reverts all of them.
    public static let noSnapshots = "none"

    public struct SnapshotSummary: Sendable, Equatable, Decodable {
        public var id: String
        public var createdAt: Date
    }

    /// Parses `macctl snapshot list --json`: `{"ok": true, "result": [{"id", "createdAt", ...}]}`, newest first.
    public static func snapshots(fromListJSON output: String) throws -> [SnapshotSummary] {
        struct Envelope: Decodable {
            var ok: Bool
            var result: [SnapshotSummary]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: Data(output.utf8))
        guard envelope.ok, let result = envelope.result else {
            throw RunnerError.failed(path: "macctl", status: 1, output: output)
        }
        return result
    }

    /// The snapshots taken after `checkpoint`, newest first: everything listed before its marker.
    /// If the marker is gone from macctl's history, falls back to snapshots created after the checkpoint.
    public static func snapshots(after checkpoint: Checkpoint, in snapshots: [SnapshotSummary]) -> [String] {
        guard let marker = checkpoint.macctlSnapshot else { return [] }
        if marker != noSnapshots, !snapshots.contains(where: { $0.id == marker }) {
            return snapshots.filter { $0.createdAt > checkpoint.createdAt }.map(\.id)
        }
        return snapshots.prefix(while: { $0.id != marker }).map(\.id)
    }

    /// Asks macctl which snapshots came after the checkpoint. Read-only.
    public func macctlSnapshots(after checkpoint: Checkpoint) async throws -> [String] {
        guard let macctlPath, checkpoint.macctlSnapshot != nil else { return [] }
        let output = try await runner(macctlPath, ["snapshot", "list", "--json"])
        let all = try Self.snapshots(fromListJSON: output)
        return Self.snapshots(after: checkpoint, in: all)
    }

    /// Oldest first.
    public func list() -> [Checkpoint] {
        guard let data = try? Data(contentsOf: storeFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Checkpoint].self, from: data)) ?? []
    }

    public func find(_ id: String?) -> Checkpoint? {
        let all = list()
        guard let id else { return all.last }
        return all.last { $0.id == id }
    }

    func save(_ checkpoints: [Checkpoint]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(checkpoints)
        try TextFile.write(String(decoding: data, as: UTF8.self) + "\n", to: storeFile)
    }

    /// The commands `undo` runs: put `~/.config` files that existed at the checkpoint commit back as they
    /// were (`git checkout <commit> -- .` never deletes files that commit lacks), keeping Summon's own
    /// checkpoint history, then `macctl undo` of each snapshot taken since, newest first (from
    /// `macctlSnapshots(after:)`), which restores every setting to its value at the checkpoint.
    /// Files created afterwards stay in place.
    public func undoSteps(_ checkpoint: Checkpoint, macctlSnapshots: [String] = []) -> [LaunchPlan] {
        var steps: [LaunchPlan] = []
        if let gitPath, let commit = checkpoint.configCommit {
            steps.append(LaunchPlan(
                executable: gitPath,
                arguments: ["-C", paths.userConfig.path, "checkout", commit, "--", ".", ":(exclude)summon/checkpoints.json"]
            ))
        }
        if let macctlPath {
            for snapshot in macctlSnapshots {
                steps.append(LaunchPlan(executable: macctlPath, arguments: ["undo", snapshot, "--json"]))
            }
        }
        return steps
    }
}
