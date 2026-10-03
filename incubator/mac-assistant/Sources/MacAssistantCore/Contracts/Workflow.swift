import Foundation

/// States of one assistant task: inspect → diagnose → preview → authorize → execute → verify →
/// report, or recover. The journal records every transition before the next step starts, and
/// refuses transitions this table does not allow.
public enum TaskState: String, Sendable, Hashable, Codable, CaseIterable {
    case created
    case inspecting
    case diagnosing
    case previewing
    case awaitingAuthorization
    case executing
    case verifying
    case recovering
    case reporting
    // Terminal.
    case completed
    case failed
    case cancelled
    /// The app stopped (crash, quit) mid-task. Found at next launch; the user decides what to do.
    case interrupted

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .interrupted: true
        default: false
        }
    }

    /// Legal next states. Any non-terminal state may also go to `.failed`, `.cancelled`, or
    /// `.interrupted`.
    public var allowedNext: Set<TaskState> {
        let next: Set<TaskState> = switch self {
        case .created: [.inspecting]
        case .inspecting: [.diagnosing, .reporting]
        // Diagnosis may ask for more evidence, propose a change, or report (read-only tasks).
        case .diagnosing: [.inspecting, .previewing, .reporting]
        case .previewing: [.awaitingAuthorization, .reporting]
        // Refusal goes to reporting with nothing changed.
        case .awaitingAuthorization: [.executing, .reporting]
        case .executing: [.verifying, .recovering]
        case .verifying: [.reporting, .recovering]
        case .recovering: [.verifying, .reporting]
        case .reporting: [.completed]
        case .completed, .failed, .cancelled, .interrupted: []
        }
        return isTerminal ? next : next.union([.failed, .cancelled, .interrupted])
    }

    public func canTransition(to next: TaskState) -> Bool {
        allowedNext.contains(next)
    }
}
