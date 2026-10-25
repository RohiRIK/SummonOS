import Foundation

/// The panel's "Needs attention" block: recent crashes grouped by program (one row each, with a count) and Summon's
/// own setup problems. Empty means the block is hidden: the panel shows problems only when there are some.
public struct PanelAttention: Sendable, Equatable {
    public struct Crash: Sendable, Equatable, Identifiable {
        public var program: String
        /// The newest report; Diagnose hands it to the agent.
        public var file: String
        public var count: Int
        public var id: String { program }

        public var title: String { count == 1 ? "\(program) crashed" : "\(program) crashed \(count) times" }
    }

    public var crashes: [Crash]
    /// Failed or warning `summon doctor` checks.
    public var setupProblems: Int

    public var isEmpty: Bool { crashes.isEmpty && setupProblems == 0 }
    public var setupTitle: String { setupProblems == 1 ? "1 setup problem · Fix…" : "\(setupProblems) setup problems · Fix…" }

    /// `reports` newest first, as the crash watcher returns them; programs keep that order.
    public init(reports: [CrashReport], doctor: DoctorReport?) {
        var crashes: [Crash] = []
        for report in reports {
            if let index = crashes.firstIndex(where: { $0.program == report.program }) {
                crashes[index].count += 1
            } else {
                crashes.append(Crash(program: report.program, file: report.file, count: 1))
            }
        }
        self.crashes = crashes
        setupProblems = doctor?.issues.count ?? 0
    }
}
