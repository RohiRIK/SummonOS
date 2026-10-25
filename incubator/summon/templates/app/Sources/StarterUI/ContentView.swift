import StarterCore
import SwiftUI

/// The main window: a sidebar of items and the selected item's detail.
public struct ContentView: View {
    @Bindable private var model: StarterModel
    @AppStorage(StarterSettings.showCountKey) private var showCount = true

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(model.library.items, selection: $model.selection) { item in
                Text(item.title)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button("New Item", systemImage: "plus") { model.addItem() }
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
        .frame(minWidth: 560, minHeight: 360)
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
    }
}

#Preview("Window") {
    ContentView(model: .preview)
}

#Preview("Empty") {
    ContentView(model: StarterModel())
}
