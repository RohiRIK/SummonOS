import AppKit
import StarterCore
import SwiftUI

/// The launcher: a 56 pt search bar that grows a results list as you type (up to about 450 pt), and a footer
/// with key hints or a status line. Everything works from the keyboard:
/// ↑↓ select, ↩ open, ⌘1…⌘9 open that row, ⌘K actions for the selected row, ⌘, Settings, Esc closes.
/// Drop a file on it and the app you pick opens that file.
public struct LauncherView: View {
    @Bindable private var model: StarterModel
    @FocusState private var fieldFocused: Bool
    @State private var dropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !model.results.isEmpty || model.status != nil || !model.query.isEmpty {
                Divider()
                if model.showingActions, let item = model.selected {
                    ActionList(model: model, item: item)
                } else if model.results.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    resultsList
                }
                Divider()
                footer
            }
        }
        .frame(width: 680)
        .launcherBackground(highlighted: dropTargeted)
        .animation(reduceMotion ? nil : .spring(duration: 0.15), value: model.results.count)
        .dropDestination(for: URL.self) { urls, _ in
            model.droppedFile = urls.first
            fieldFocused = true
            return urls.first != nil
        } isTargeted: { dropTargeted = $0 }
        .onAppear { fieldFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let file = model.droppedFile {
                FileChip(url: file) { model.droppedFile = nil }
            }
            TextField(model.droppedFile == nil ? "Open an app" : "Open it with…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($fieldFocused)
                .onSubmit { model.runSelected() }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.escape) {
                    guard model.showingActions else { return .ignored } // Esc then closes the panel
                    model.showingActions = false
                    return .handled
                }
                .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters)) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    return command(press.characters)
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        ResultRow(item: item, index: index, selected: index == model.selection)
                            .id(item.id)
                            .onTapGesture { model.run(at: index) }
                            .contextMenu {
                                Button("Open") { model.open(item) }
                                Button("Show in Finder") { model.reveal(item) }
                                Button("Copy Path") { model.copyPath(item) }
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.selection) {
                if let id = model.selected?.id { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let status = model.status {
                Text(status).lineLimit(1)
            } else {
                Text(model.results.count == 1 ? "1 app" : "\(model.results.count) apps")
            }
            Spacer()
            KeyHint(key: "↩", label: "Open")
            KeyHint(key: "⌘K", label: "Actions")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    /// ⌘1…⌘9, ⌘K and ⌘, while the field has focus.
    private func command(_ characters: String) -> KeyPress.Result {
        if let digit = Int(characters), (1...9).contains(digit) {
            model.run(at: digit - 1)
            return .handled
        }
        switch characters.lowercased() {
        case "k":
            if model.selected != nil { model.showingActions.toggle() }
            return .handled
        case ",":
            model.requestSettings()
            return .handled
        default:
            return .ignored
        }
    }
}

/// One result: the app's icon, its name, and the ⌘ number that opens it.
struct ResultRow: View {
    let item: Launchable
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.body.weight(.medium))
            Spacer()
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.tint.opacity(0.25))
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The ⌘K list, in place of the results: every action for the selected row, so the mouse is never needed.
/// Esc goes back to the results.
struct ActionList: View {
    let model: StarterModel
    let item: Launchable

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            ActionRow(title: "Open", key: "↩") { model.open(item) }
            ActionRow(title: "Show in Finder", key: nil) { model.reveal(item) }
            ActionRow(title: "Copy Path", key: nil) { model.copyPath(item) }
        }
        .padding(6)
    }
}

struct ActionRow: View {
    let title: String
    let key: String?
    let action: @MainActor () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let key { Text(key).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                if hovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A dropped file, shown as a chip before the query. × removes it.
struct FileChip: View {
    let url: URL
    let remove: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(url.lastPathComponent).lineLimit(1).frame(maxWidth: 160)
            Button("Remove File", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Text(key)
                .font(.caption.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

extension View {
    /// The launcher's own surface: Liquid Glass on macOS 26 (a floating control, like Spotlight), a thick
    /// material before, with a hairline border so it stands out over busy windows. Tinted while a file hovers.
    @ViewBuilder
    func launcherBackground(highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Group {
            if #available(macOS 26, *) {
                glassEffect(.regular, in: shape)
            } else {
                background(.thickMaterial, in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: highlighted ? 2 : 1)
        }
        .clipShape(shape)
    }
}

#Preview("Results") {
    LauncherView(model: .preview)
}

#Preview("Bar") {
    LauncherView(model: StarterModel())
}
