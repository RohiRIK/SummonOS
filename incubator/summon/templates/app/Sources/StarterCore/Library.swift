import Foundation

/// The app's one piece of logic: an ordered list of named items. Replace it with your app's Core
/// (documents, services, parsers), Foundation only, tested in StarterCoreTests.
public struct Library: Equatable, Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var title: String
    }

    public private(set) var items: [Item]

    public init(items: [Item] = []) {
        self.items = items
    }

    /// Adds "Untitled", "Untitled 2", … and returns the new item's id.
    @discardableResult
    public mutating func add(id: UUID = UUID()) -> UUID {
        let taken = Set(items.map(\.title))
        var title = "Untitled"
        var number = 2
        while taken.contains(title) {
            title = "Untitled \(number)"
            number += 1
        }
        items.append(Item(id: id, title: title))
        return id
    }

    /// Blank titles are ignored, so an item never loses its name.
    public mutating func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = trimmed
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func item(_ id: UUID?) -> Item? {
        items.first { $0.id == id }
    }
}
