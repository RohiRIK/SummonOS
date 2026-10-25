import StarterCore
import SwiftUI

/// The main window: a searchable sidebar of items, the selected item in the content area, and an inspector.
/// Resizable from 800 × 550 up, full screen and Split View included. Every action is in the menu bar with its
/// shortcut and in each row's context menu; deletes are undoable instead of confirmed.
public struct ContentView: View {
    @Bindable private var model: StarterModel
    @AppStorage(StarterSettings.showCountKey) private var showCount = true
    @Environment(\.undoManager) private var undoManager
    @FocusState private var searchFocused: Bool

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(model.visibleItems, selection: $model.selection) { item in
                Text(item.title)
                    .contextMenu {
                        Button("Delete") { model.delete(item.id) }
                    }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .overlay {
                if model.visibleItems.isEmpty && !model.search.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showCount {
                    Text(model.library.items.count == 1 ? "1 item" : "\(model.library.items.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassControl(cornerRadius: 10)
                        .padding(8)
                }
            }
        } detail: {
            if let item = model.library.item(model.selection) {
                DetailView(item: item) { model.rename(item.id, to: $0) }
            } else {
                ContentUnavailableView("No Item Selected", systemImage: "square.dashed",
                                       description: Text("Choose an item, or press ⌘N for a new one."))
            }
        }
        .searchable(text: $model.search, placement: .sidebar, prompt: "Search")
        .searchFocused($searchFocused)
        .inspector(isPresented: $model.showsInspector) {
            InspectorView(item: model.library.item(model.selection), position: position)
                .inspectorColumnWidth(min: 200, ideal: 240, max: 320)
        }
        .toolbar {
            ToolbarItem {
                Button("New Item", systemImage: "plus") { model.addItem() }
            }
            ToolbarItem {
                Button("Show Inspector", systemImage: "sidebar.trailing") { model.showsInspector.toggle() }
                    .help("Show or hide the inspector (⌥⌘I)")
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .showsOnboardingOnFirstLaunch()
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .onChange(of: model.findRequest) { searchFocused = true }
    }

    private var position: String? {
        guard let index = model.library.items.firstIndex(where: { $0.id == model.selection }) else { return nil }
        return "\(index + 1) of \(model.library.items.count)"
    }
}

/// One item: its title, editable.
struct DetailView: View {
    let item: Library.Item
    let rename: (String) -> Void
    @State private var title = ""

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .onSubmit { rename(title) }
        }
        .formStyle(.grouped)
        .navigationTitle(item.title)
        .onAppear { title = item.title }
        .onChange(of: item.id) { title = item.title }
    }
}

/// Facts about the selected item. The inspector shows details; edits stay in the content area.
struct InspectorView: View {
    let item: Library.Item?
    let position: String?

    var body: some View {
        if let item {
            Form {
                LabeledContent("Title", value: item.title)
                LabeledContent("Characters", value: "\(item.title.count)")
                if let position { LabeledContent("Position", value: position) }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "info.circle")
        }
    }
}

/// Menu bar commands, so every action has a menu item and a shortcut.
public struct StarterCommands: Commands {
    private let model: StarterModel

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item") { model.addItem() }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .pasteboard) {
            Button("Delete Item") { model.deleteSelection() }
                .keyboardShortcut(.delete)
                .disabled(model.selection == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") { model.find() }
                .keyboardShortcut("f")
        }
        CommandGroup(after: .sidebar) {
            Button(model.showsInspector ? "Hide Inspector" : "Show Inspector") { model.showsInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

#Preview("Window") {
    ContentView(model: .preview)
}

#Preview("Empty") {
    ContentView(model: StarterModel())
}
