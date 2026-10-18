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
}
