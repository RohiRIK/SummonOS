import Foundation
import StarterCore
import Testing

@Suite struct LibraryTests {
    @Test func newItemsGetUniqueNames() {
        var library = Library()
        library.add()
        library.add()
        library.add()
        #expect(library.items.map(\.title) == ["Untitled", "Untitled 2", "Untitled 3"])
    }

    @Test func renameTrimsAndIgnoresBlank() {
        var library = Library()
        let id = library.add()
        library.rename(id, to: "  Groceries ")
        #expect(library.item(id)?.title == "Groceries")
        library.rename(id, to: "   ")
        #expect(library.item(id)?.title == "Groceries")
    }

    @Test func removeDropsOnlyThatItem() {
        var library = Library()
        let first = library.add()
        let second = library.add()
        library.remove(first)
        #expect(library.items.map(\.id) == [second])
        #expect(library.item(first) == nil)
    }

    @Test func removeThenInsertRestoresThePlace() throws {
        var library = Library()
        let first = library.add()
        let second = library.add()
        let third = library.add()
        // Mutating calls stay outside #expect/#require (the macros capture their arguments).
        let result = library.remove(second)
        let removed = try #require(result)
        #expect(removed.index == 1)
        #expect(library.items.map(\.id) == [first, third])
        library.insert(removed.item, at: removed.index)
        #expect(library.items.map(\.id) == [first, second, third])
        library.insert(removed.item, at: 0) // already there
        #expect(library.items.count == 3)
        let missing = library.remove(UUID())
        #expect(missing == nil)
    }

    @Test func matchingIgnoresCaseAndBlankQueries() {
        var library = Library()
        let id = library.add()
        library.rename(id, to: "Groceries")
        library.add()
        #expect(library.matching("groc").map(\.id) == [id])
        #expect(library.matching("  ").count == 2)
        #expect(library.matching("zzz").isEmpty)
    }
}
