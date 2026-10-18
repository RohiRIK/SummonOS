import Foundation
import Observation
import StarterCore

/// UI state for the window. Views read it; Core does the work.
@MainActor
@Observable
public final class StarterModel {
    public private(set) var library: Library
    public var selection: UUID?

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

    public func deleteSelection() {
        guard let selection else { return }
        let index = library.items.firstIndex { $0.id == selection } ?? 0
        library.remove(selection)
        self.selection = library.items.indices.contains(index) ? library.items[index].id : library.items.last?.id
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
