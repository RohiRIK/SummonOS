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
        }
    }
}
