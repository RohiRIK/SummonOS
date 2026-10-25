import AppKit
import StarterCore
import SwiftUI

/// The notch panel. Closed, it is a black shape the size of the camera housing, so it vanishes into it. Open,
/// it grows down out of the housing into the shelf: files you dropped, to drag out again, open, or reveal.
/// Drag a file onto the notch and it opens to take it. Text is light on black in both modes.
public struct NotchView: View {
    private let model: StarterModel

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: model.isOpen ? 20 : 8, bottomTrailingRadius: model.isOpen ? 20 : 8,
                                   style: .continuous)
                .fill(.black) // true black hides the seam with the housing (a convention, not an Apple rule)
            if model.isOpen {
                ShelfView(model: model)
                    .padding(.top, model.topInset + 6)
                    .padding([.horizontal, .bottom], 14)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: model.isOpen)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return !urls.isEmpty
        } isTargeted: { model.setDropTargeted($0) }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shelf")
    }
}

struct ShelfView: View {
    let model: StarterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shelf").font(.headline)
                Text(model.shelf.files.isEmpty ? "" : "\(model.shelf.files.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.shelf.files.isEmpty {
                    Button("Clear", action: model.clear)
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
            }
            if model.shelf.files.isEmpty {
                Label("Drop files here to keep them close", systemImage: "tray.and.arrow.down")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.shelf.files, id: \.self) { url in
                            FileTile(url: url, model: model)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .foregroundStyle(.white)
    }
}

/// One shelved file: drag it out to use it (it stays on the shelf), click to open, right-click for more.
struct FileTile: View {
    let url: URL
    let model: StarterModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(4)
        .background(hovering ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { model.open(url) }
        .draggable(url)
        .contextMenu {
            Button("Open") { model.open(url) }
            Button("Show in Finder") { model.reveal(url) }
            Divider()
            Button("Remove from Shelf") { model.remove(url) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help(url.path)
    }
}

#Preview("Open") {
    NotchView(model: .preview).frame(width: 480, height: 160)
}

#Preview("Empty") {
    NotchView(model: StarterModel(shelf: Shelf())).frame(width: 480, height: 160)
}
