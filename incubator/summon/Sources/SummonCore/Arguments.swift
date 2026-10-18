/// Hand-rolled argument handling for `summon` (no third-party dependencies).
/// Flags may appear anywhere; everything else stays positional, in order.
public struct Arguments: Sendable, Equatable {
    public private(set) var items: [String]

    public init(_ items: [String]) {
        self.items = items
    }

    /// Removes `name` if present and reports whether it was.
    public mutating func flag(_ name: String) -> Bool {
        guard let index = items.firstIndex(of: name) else { return false }
        items.remove(at: index)
        return true
    }

    /// Removes `name value` (or `name=value`) and returns the value.
    public mutating func option(_ name: String) -> String? {
        if let index = items.firstIndex(of: name) {
            let next = items.index(after: index)
            guard next < items.endIndex else {
                items.remove(at: index)
                return nil
            }
            let value = items[next]
            items.removeSubrange(index...next)
            return value
        }
        if let index = items.firstIndex(where: { $0.hasPrefix(name + "=") }) {
            let value = String(items[index].dropFirst(name.count + 1))
            items.remove(at: index)
            return value
        }
        return nil
    }

    /// Removes and returns the first positional item.
    public mutating func next() -> String? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    public var isEmpty: Bool { items.isEmpty }
}
