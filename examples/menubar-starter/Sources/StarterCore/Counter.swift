/// The app's one piece of logic: a click counter. Replace it with your plugin's Core
/// (services, parsers, tool wrappers), Foundation only, tested in StarterCoreTests.
public struct Counter: Equatable, Sendable {
    public private(set) var value: Int

    public init(value: Int = 0) {
        self.value = max(0, value)
    }

    public mutating func increment() {
        value += 1
    }

    public mutating func reset() {
        value = 0
    }

    public var label: String {
        value == 1 ? "1 click" : "\(value) clicks"
    }
}
