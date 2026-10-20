import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Deterministic crash injection for the kill -9 matrix. A no-op unless the process runs with
/// `MACCTL_TEST_MODE=1` and `MACCTL_FAILPOINT` set:
///
/// - `MACCTL_FAILPOINT=<name>` sends SIGKILL to this process the first time `<name>` is reached;
///   `<name>@<n>` on the n-th time (for example the second change of a batch). No `defer`, no
///   `atexit`, no buffered output runs: it is a real kill -9.
/// - `MACCTL_FAILPOINT=list` prints every known point name (one per line, stdout) and exits 0
///   before anything else runs, so nothing is read or written.
/// - `MACCTL_FAILPOINT=trace` runs normally and prints `failpoint <name>@<n>` to stderr at every
///   point it passes. The crash matrix uses it to generate its cases.
///
/// `Failpoint.all` is the single source of truth. `hit` refuses a name that is not listed
/// (programmer error), and the matrix fails when a listed point is never reached by any case.
public enum Failpoint {
    /// Every point, in the order a mutation reaches them (ADR D2 write order).
    public static let all: [String] = [
        // Session start (apply / undo / recover all take the lock first).
        "lock.acquired",
        "plan.done",
        // Session header (`snapshots/<id>.json`): 0600 temp, fsync, exclusive link, dir fsync.
        "snapshot.tmp-written",
        "snapshot.tmp-synced",
        "snapshot.linked",
        "snapshot.dir-synced",
        // Journal file (`journal/<id>.jsonl`), created O_EXCL 0600.
        "journal.created",
        "journal.dir-synced",
        // Per change: intent is durable before the real write; applied (or failed) after read-back.
        "change.intent-appended",
        "change.intent-synced",
        "change.written",
        "change.synchronized",
        "change.read-back",
        "change.applied-appended",
        "change.applied-synced",
        "change.failed-appended",
        "change.failed-synced",
        // After the batch.
        "restarts.before",
        "restarts.after",
        "session-end.appended",
        "session-end.synced",
        // Header status rewrite: 0600 temp, fsync, rename, dir fsync.
        "status.tmp-written",
        "status.renamed",
        "status.synced",
        "lock.releasing",
        // Recovery (`macctl recover`, or `undo <id>` of an unresolved session).
        "recover.lock-acquired",
        "recover.resolve-appended",
        "recover.resolve-synced",
        "revert.intent-appended",
        "revert.intent-synced",
        "revert.written",
        "revert.synchronized",
        "revert.reverted-appended",
        "revert.reverted-synced",
        "revert.flagged-appended",
        "revert.flagged-synced",
        "recover.restarts-before",
        "recover.restarts-after",
        "recover.session-end-appended",
        "recover.session-end-synced",
    ]

    enum Mode: Equatable {
        case off
        case list
        case trace
        case kill(name: String, occurrence: Int)
    }

    /// Parses the environment. Failpoints are honoured only in test mode.
    static func mode(_ environment: [String: String]) -> Mode {
        guard environment["MACCTL_TEST_MODE"] == "1", let spec = environment["MACCTL_FAILPOINT"],
              !spec.isEmpty else { return .off }
        switch spec {
        case "list": return .list
        case "trace": return .trace
        default:
            let parts = spec.split(separator: "@", maxSplits: 1).map(String.init)
            let occurrence = parts.count == 2 ? Int(parts[1]) ?? 1 : 1
            return .kill(name: parts[0], occurrence: max(1, occurrence))
        }
    }

    private static let state = FailpointState(mode: mode(ProcessInfo.processInfo.environment))

    /// Whether `MACCTL_FAILPOINT` names a point that does not exist (the CLI refuses to start).
    public static var unknownRequestedPoint: String? {
        if case .kill(let name, _) = state.mode, !all.contains(name) { return name }
        return nil
    }

    /// `MACCTL_FAILPOINT=list`: the CLI prints `all` and exits before parsing arguments.
    public static var listRequested: Bool { state.mode == .list }

    /// Marks one step. Kills the process when this is the requested point and occurrence.
    public static func hit(_ name: String) {
        precondition(all.contains(name), "Unknown failpoint \(name); add it to Failpoint.all")
        guard state.mode != .off else { return }
        let count = state.count(name)
        switch state.mode {
        case .trace:
            FileHandle.standardError.write(Data("failpoint \(name)@\(count)\n".utf8))
        case .kill(let target, let occurrence) where target == name && occurrence == count:
            kill(getpid(), SIGKILL)
            // SIGKILL cannot be caught; never continue past a requested crash.
            while true { pause() }
        default:
            break
        }
    }
}

private final class FailpointState: @unchecked Sendable {
    let mode: Failpoint.Mode
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(mode: Failpoint.Mode) { self.mode = mode }

    func count(_ name: String) -> Int {
        lock.withLock {
            counts[name, default: 0] += 1
            return counts[name]!
        }
    }
}
