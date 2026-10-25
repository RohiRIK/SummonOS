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

    /// Removes the item and says where it was, so the delete can be undone with `insert(_:at:)`.
    @discardableResult
    public mutating func remove(_ id: UUID) -> (item: Item, index: Int)? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return (items.remove(at: index), index)
    }

    /// Puts a removed item back (undo). An out-of-range index appends; an item already present is ignored.
    public mutating func insert(_ item: Item, at index: Int) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: min(max(0, index), items.count))
    }

    /// Items whose title contains `query`, ignoring case and accents; all items for an empty query.
    public func matching(_ query: String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.title.localizedStandardContains(trimmed) }
    }

    public func item(_ id: UUID?) -> Item? {
        items.first { $0.id == id }
    }
}
