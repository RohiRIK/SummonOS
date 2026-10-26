import Foundation

/// The panel's "Needs attention" line: Summon's own setup problems. Empty means the line is hidden. Crashes are not
/// here (owner, 2026-10-26): they arrive as a notification and stay in Activity.
public struct PanelAttention: Sendable, Equatable {
    /// Failed or warning `summon doctor` checks.
    public var setupProblems: Int

    public var isEmpty: Bool { setupProblems == 0 }

    /// The panel's single status line (Fix… hands the problems to the agent).
    public var summary: String? { setupProblems > 0 ? setupTitle : nil }

    public var setupTitle: String { setupProblems == 1 ? "1 setup problem · Fix…" : "\(setupProblems) setup problems · Fix…" }

    public init(doctor: DoctorReport?) {
        setupProblems = doctor?.issues.count ?? 0
    }
}
