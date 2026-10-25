import Foundation
import Observation
import StarterCore

/// UI state for the window. Views read it; Core does the work.
@MainActor
@Observable
public final class StarterModel {
    public private(set) var library: Library
    public var selection: UUID?
    public var search = ""
    public var showsInspector = true
    /// Bumped by Find… (⌘F); the sidebar's search field takes focus.
    public private(set) var findRequest = 0
    /// The window's undo manager, set by ContentView, so deletes from the menu bar can be undone too.
    @ObservationIgnored public weak var undoManager: UndoManager?

    public init(library: Library = Library()) {
        self.library = library
        selection = library.items.first?.id
    }

    public func addItem() {
        selection = library.add()
    }

    public func rename(_ id: UUID, to title: String) {
        library.rename(id, to: title)
    }

    /// The sidebar's rows: every item, or those matching the search.
    public var visibleItems: [Library.Item] { library.matching(search) }

    public func deleteSelection() {
        if let selection { delete(selection) }
    }

    /// Deletes without asking: Edit › Undo (⌘Z) brings it back (HIG: undo over confirmation).
    public func delete(_ id: UUID) {
        guard let removed = library.remove(id) else { return }
        let item = removed.item, index = removed.index
        if selection == id {
            selection = library.items.indices.contains(index) ? library.items[index].id : library.items.last?.id
        }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(item, at: index) }
        }
        undoManager?.setActionName("Delete \(item.title)")
    }

    private func restore(_ item: Library.Item, at index: Int) {
        library.insert(item, at: index)
        selection = item.id
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.delete(item.id) }
        }
        undoManager?.setActionName("Delete \(item.title)")
    }

    public func find() {
        findRequest += 1
    }

    public static var preview: StarterModel {
        var library = Library()
        let first = library.add()
        library.rename(first, to: "Groceries")
        library.add()
        return StarterModel(library: library)
    }
}

/// UserDefaults keys shared by the Settings window and the views that read them.
public enum StarterSettings {
    public static let showCountKey = "showItemCount"
}
