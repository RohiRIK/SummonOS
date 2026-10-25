/// The first-run setup's steps (HIG Onboarding: fast and optional). The permissions step is there only when the
/// app has a permission it can't work without; ask for the rest the first time a feature needs it (HIG Privacy).
public struct OnboardingFlow: Equatable, Sendable {
    public enum Step: String, Equatable, Sendable {
        /// What the app does, in a sentence and a few rows.
        case welcome
        /// Permission cards with live status and a link to System Settings.
        case permissions
        /// Where the app lives (the menu bar icon, the window) and the one thing to try first.
        case ready
    }

    public let steps: [Step]
    public private(set) var index = 0

    public init(needsPermissions: Bool) {
        steps = needsPermissions ? [.welcome, .permissions, .ready] : [.welcome, .ready]
    }

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

    /// UserDefaults key: set when setup is finished or closed (closing skips it; Settings can show it again).
    public static let completedKey = "onboardingCompleted"
}
