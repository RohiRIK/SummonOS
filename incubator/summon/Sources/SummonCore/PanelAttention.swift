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

    /// The panel's single status line: crashes first (Review… opens Activity's problems), else setup problems (Fix…).
    public var summary: String? {
        if !crashes.isEmpty {
            let apps = crashes.count == 1 ? "\(crashes[0].program) crashed" : "\(crashes.count) apps crashed"
            return apps + " · Review…"
        }
        return setupProblems > 0 ? setupTitle : nil
    }

    /// Background helpers and test runners ("Helium Helper", "swiftpm-testing-helper", "xctest", Apple's XPC services):
    /// their crashes stay in Activity but don't flag the panel.
    public static func isHelper(_ program: String) -> Bool {
        let name = program.lowercased()
        return name.contains("helper") || name.hasPrefix("swiftpm-") || name.contains("xctest") || name.hasPrefix("com.apple.")
    }

    public var setupTitle: String { setupProblems == 1 ? "1 setup problem · Fix…" : "\(setupProblems) setup problems · Fix…" }

    /// `reports` newest first, as the crash watcher returns them; programs keep that order.
    public init(reports: [CrashReport], doctor: DoctorReport?) {
        var crashes: [Crash] = []
        // Only apps the person uses count; helpers and test runners stay in Activity (owner, 2026-10-25).
        for report in reports where !Self.isHelper(report.program) {
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
