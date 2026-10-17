import Foundation

/// Taken before every summoned agent session so `summon checkpoint undo` can put things back:
/// a macctl snapshot of system settings, and a git commit of `~/.config` when it is a repo.
/// Recorded in `~/.config/summon/checkpoints.json`, newest last.
public struct Checkpoint: Sendable, Equatable, Codable, Identifiable {
    /// `yyyyMMdd-HHmmss`, unique enough for a person taking checkpoints by hand.
    public var id: String
    public var label: String
    public var createdAt: Date
    /// Commit hash in `~/.config`, when it is a git repo.
    public var configCommit: String?
    /// What `macctl snapshot create` printed (its snapshot id), when a snapshot was taken.
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
            steps.append(LaunchPlan(executable: macctlPath, arguments: ["snapshot", "create", "--label", label]))
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
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    snapshot = Self.snapshotID(fromOutput: trimmed)
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

    /// macctl may print a line or JSON; take a JSON `id` if there is one, else the last non-empty line.
    static func snapshotID(fromOutput output: String) -> String {
        if let data = output.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let id = object["id"] as? String {
            return id
        }
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.last ?? "latest"
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
    /// checkpoint history, then macctl undo of that snapshot. Files created afterwards stay in place.
    public func undoSteps(_ checkpoint: Checkpoint) -> [LaunchPlan] {
        var steps: [LaunchPlan] = []
        if let gitPath, let commit = checkpoint.configCommit {
            steps.append(LaunchPlan(
                executable: gitPath,
                arguments: ["-C", paths.userConfig.path, "checkout", commit, "--", ".", ":(exclude)summon/checkpoints.json"]
            ))
        }
        if let macctlPath, let snapshot = checkpoint.macctlSnapshot {
            steps.append(LaunchPlan(executable: macctlPath, arguments: snapshot == "latest" ? ["undo"] : ["undo", snapshot]))
        }
        return steps
    }
}
