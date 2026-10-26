/// Summon's first-run setup (docs/ux-surfaces/06-onboarding.md): what Summon does, choose the agent, allow
/// Accessibility, then see where Summon lives. Short and optional: closing the window skips it, and Settings › General shows it again.
public struct OnboardingFlow: Equatable, Sendable {
    public enum Step: String, CaseIterable, Equatable, Sendable {
        /// A short brand moment and what Summon does.
        case welcome
        /// Which coding agent it uses, and whether that agent is logged in.
        case agent
        /// Accessibility, explained before System Settings opens, with a live check.
        case accessibility
        /// The menu bar icon and the panel hotkey.
        case ready
    }

    public let steps = Step.allCases
    public private(set) var index = 0

    public init() {}

    public var step: Step { steps[index] }
    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == steps.count - 1 }

    /// Moves on; false on the last step, which means "done".
    public mutating func next() -> Bool {
        guard !isLast else { return false }
        index += 1
        return true
    }

    public mutating func back() {
        if index > 0 { index -= 1 }
    }

    /// UserDefaults key, set once setup is finished, closed, or found unnecessary.
    public static let completedKey = "summon.onboarding.completed"

    public enum Launch: Equatable, Sendable {
        /// Open the setup window.
        case show
        /// Nothing left to set up (an update from before onboarding existed): record it as done, show nothing.
        case markCompleted
        /// Already done, or a Visual QA run: do nothing.
        case none
    }

    /// What a launch does about the setup window.
    public static func launch(completed: Bool, visualQA: Bool, hasDefaultAgent: Bool,
                              accessibilityGranted: Bool) -> Launch {
        if completed || visualQA { return .none }
        return hasDefaultAgent && accessibilityGranted ? .markCompleted : .show
    }
}
