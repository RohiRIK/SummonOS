import Foundation

/// Every failure the CLI reports. `exitCode` is the process exit status.
public enum MacCtlError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownSetting(String)
    case invalidValue(id: String, value: String, reason: String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case permissionMissing(Permission, settingsURL: String)
    case needsConfirmation(id: String, risk: Risk)
    case unsupported(id: String, reason: String)
    case snapshotNotFound(String)
    case noSnapshots
    case invalidProfile(String)
    case snapshotExists(String)
    case transactionBusy
    case mutationFailed(snapshotID: String, appliedSettings: [String], reason: String)
    case invalidTestMode(String)
    case managedSetting(id: String)
    case recoveryPending(snapshotID: String)
    case journalCorrupt(snapshotID: String, line: Int)
    case partialRestore(snapshotID: String, flagged: [String])

    public var exitCode: Int32 {
        switch self {
        case .permissionMissing: 2
        case .needsConfirmation: 3
        case .unsupported: 4
        default: 1
        }
    }

    /// Stable machine-readable code for `--json` output.
    public var code: String {
        switch self {
        case .unknownSetting: "unknown_setting"
        case .invalidValue: "invalid_value"
        case .commandFailed: "command_failed"
        case .permissionMissing: "permission_missing"
        case .needsConfirmation: "needs_confirmation"
        case .unsupported: "unsupported"
        case .snapshotNotFound: "snapshot_not_found"
        case .noSnapshots: "no_snapshots"
        case .invalidProfile: "invalid_profile"
        case .snapshotExists: "snapshot_exists"
        case .transactionBusy: "transaction_busy"
        case .mutationFailed: "mutation_failed"
        case .invalidTestMode: "invalid_test_mode"
        case .managedSetting: "managed_setting"
        case .recoveryPending: "recovery_pending"
        case .journalCorrupt: "journal_corrupt"
        case .partialRestore: "partial_restore"
        }
    }

    public var description: String {
        switch self {
        case .unknownSetting(let id): "Unknown setting \(id). Run `macctl list`."
        case .invalidValue(let id, let value, let reason): "Invalid value \(value) for \(id): \(reason)"
        case .commandFailed(let command, let code, let stderr): "\(command) failed (\(code)): \(stderr)"
        case .permissionMissing(let p, let url): "Missing permission \(p). Grant it in System Settings: \(url)"
        case .needsConfirmation(let id, let risk): "\(id) is \(risk.rawValue) risk; pass --yes to apply."
        case .unsupported(let id, let reason): "\(id) is not supported here: \(reason)"
        case .snapshotNotFound(let id): "No snapshot \(id). Run `macctl snapshot list`."
        case .noSnapshots: "No snapshots to undo."
        case .invalidProfile(let reason): "Invalid profile: \(reason)"
        case .snapshotExists(let id): "Snapshot \(id) already exists; the original backup was preserved."
        case .transactionBusy: "Another macctl mutation is still running; retry when it finishes."
        case .invalidTestMode(let reason): "Invalid test mode: \(reason)"
        case .managedSetting(let id): "\(id) is managed by a configuration profile (forced); macctl will not change it."
        case .recoveryPending(let id): "recovery_pending \(id): an earlier macctl operation did not finish. Run `macctl recover` first."
        case .journalCorrupt(let id, let line):
            "journal_corrupt \(id): line \(line) of its journal is unreadable, so it cannot be recovered automatically. Nothing was written. Inspect journal/\(id).jsonl, then set it aside with `macctl recover --abandon \(id)` (the file is kept as \(id).jsonl.corrupt)."
        case .partialRestore(let id, let flagged):
            "partial_restore \(id): left as they are: \(flagged.joined(separator: ", ")) (changed after macctl wrote them, or the old value can no longer be restored). Everything else was restored. To overwrite hand edits: macctl undo \(id) --force"
        case .mutationFailed(let id, let applied, let reason):
            "Change failed: \(reason). Session \(id) was rolled back; \(applied.isEmpty ? "nothing is left changed" : "still changed: \(applied.joined(separator: ", ")) (see `macctl snapshot show \(id)`; `macctl recover` finishes an interrupted rollback)")."
        }
    }
}
