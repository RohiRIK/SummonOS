import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Deterministic crash injection for the kill -9 matrix. A no-op unless the process runs with
/// `MACCTL_TEST_MODE=1` and `MACCTL_FAILPOINT` set:
///
/// - `MACCTL_FAILPOINT=<point>` sends SIGKILL to this process the first time `<point>` is reached;
///   `<point>@<n>` on the n-th time. No `defer`, no `atexit`, no buffered output runs: a real kill -9.
/// - `MACCTL_FAILPOINT=list` prints every point template (one per line) and exits 0 before
///   anything else runs, so nothing is read or written.
/// - `MACCTL_FAILPOINT=trace` runs normally and prints `failpoint <point>@<n>` to stderr at every
///   point it passes. The crash matrix uses it to generate its cases.
///
/// Points are the ADR D2 canonical list, in write order. `i` is the 1-based change number within a
/// session; `j` is the change number a revert walk restores (apply rollback, undo and recover walk
/// newest first, so `RI3` comes before `RI2`). `Failpoint.all` is the single source of truth: `hit`
/// refuses a name that matches no template, and the matrix fails when a template is never reached.
public enum Failpoint {
    public static let all: [String] = [
        "H1",   // snapshot header durable (written once), before session_start
        "K1",   // session_start durable, before I1.1
        "Ii.1", // before appending intent i
        "Ii.2", // intent i appended, before F_FULLFSYNC
        "Ii.3", // intent i durable, before the real write
        "Wi.1", // real write done (CFPreferencesSetValue), before synchronize
        "Wi.2", // synchronized, before read-back
        "Ai.1", // read back as written, before appending applied i
        "Ai.2", // applied i durable
        "Fi.1", // write threw or read-back differed, before appending failed i
        "Fi.2", // failed i durable, before the immediate rollback
        "K2",   // last Ai.2, before the restarts
        "E1",   // restarts done, before session_end
        "K3",   // session_end durable, before unlock
        "RIj",  // revert walk: revert_intent j durable, before the restore write
        "RVj",  // revert walk: restore j written and synchronized, before reverted
        "R0",   // recover: lock held, before the scan
        "RE",   // recover: session_end{recovered} durable (per session, use RE@n), before the next or unlock
    ]

    /// The template a concrete point belongs to (`I2.3` → `Ii.3`, `RV1` → `RVj`), or nil.
    public static func template(of name: String) -> String? {
        if all.contains(name), !name.contains("i"), !name.contains("j") { return name }
        for prefix in ["RI", "RV"] where name.hasPrefix(prefix) {
            if let n = Int(name.dropFirst(2)), n >= 1 { return "\(prefix)j" }
        }
        guard let letter = name.first, "IWAF".contains(letter) else { return nil }
        let parts = name.dropFirst().split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let n = Int(parts[0]), n >= 1 else { return nil }
        let candidate = "\(letter)i.\(parts[1])"
        return all.contains(candidate) ? candidate : nil
    }

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

    /// While a backend write runs: the name of its post-write and post-sync points (`W3.1`, `W3.2`),
    /// or nil (revert walks, which use `RVj` after both).
    @TaskLocal public static var writePoints: (String, String)? = nil

    private static let state = FailpointState(mode: mode(ProcessInfo.processInfo.environment))

    /// Whether `MACCTL_FAILPOINT` names a point that does not exist (the CLI refuses to start).
    public static var unknownRequestedPoint: String? {
        if case .kill(let name, _) = state.mode, template(of: name) == nil { return name }
        return nil
    }

    /// `MACCTL_FAILPOINT=list`: the CLI prints `all` and exits before parsing arguments.
    public static var listRequested: Bool { state.mode == .list }

    /// `MACCTL_TEST_ENOSPC=header|intent[@n]` (test mode only): the n-th header write or intent append
    /// fails with ENOSPC before any byte is written, as on a full disk (QA plan E-diskfull).
    static func diskFullMode(_ environment: [String: String]) -> (site: String, occurrence: Int)? {
        guard environment["MACCTL_TEST_MODE"] == "1", let spec = environment["MACCTL_TEST_ENOSPC"], !spec.isEmpty
        else { return nil }
        let parts = spec.split(separator: "@", maxSplits: 1).map(String.init)
        return (parts[0], parts.count == 2 ? max(1, Int(parts[1]) ?? 1) : 1)
    }

    private static let diskFull = diskFullMode(ProcessInfo.processInfo.environment)
    private static let diskFullState = FailpointState(mode: .off)

    /// Whether `MACCTL_TEST_ENOSPC` names a site that does not exist (the CLI refuses to start).
    public static var unknownDiskFullSite: String? {
        guard let site = diskFull?.site, !["header", "intent"].contains(site) else { return nil }
        return site
    }

    /// Throws ENOSPC when `MACCTL_TEST_ENOSPC` asks for this site and occurrence. Otherwise a no-op.
    static func checkDiskFull(_ site: String) throws {
        guard let diskFull, diskFull.site == site else { return }
        if diskFullState.count(site) == diskFull.occurrence { throw POSIXError(.ENOSPC) }
    }

    /// Marks one step. Kills the process when this is the requested point and occurrence.
    public static func hit(_ name: String) {
        precondition(template(of: name) != nil, "Unknown failpoint \(name); add it to Failpoint.all")
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
