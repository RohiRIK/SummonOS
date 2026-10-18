import Observation
import StarterCore

/// UI state for the panel. Views read it; Core does the work.
@MainActor
@Observable
public final class StarterModel {
    public private(set) var counter = Counter()

    public init() {}

    public func increment() {
        counter.increment()
    }

    public func reset() {
        counter.reset()
    }
}

/// UserDefaults keys shared by the Settings window and the menu bar label.
public enum StarterSettings {
    public static let showCountKey = "showCountInMenuBar"
}
