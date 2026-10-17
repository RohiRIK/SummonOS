import AppKit
import SummonCore
import SwiftUI

/// The Summon Menu: one searchable, keyboard-first tree (Omarchy's Super+Space menu), shown in a
/// non-activating panel so it opens over any app without stealing it.
public struct LauncherView: View {
    let model: SummonModel
    let onClose: () -> Void

    @State private var query = ""
    @State private var level: String?
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    public init(model: SummonModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    private var rows: [MenuItem] {
        query.isEmpty ? model.visibleChildren(of: level) : model.menu.search(query).filter { model.visibility[$0.id] != false }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                if let level {
                    Text(model.menu.path(to: level).joined(separator: " › "))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TextField(level == nil ? "Search Summon" : "Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit(activateSelection)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { back(); return .handled }
                    .onKeyPress(.rightArrow) {
                        guard query.isEmpty else { return .ignored }
                        activateSelection()
                        return .handled
                    }
                    .onKeyPress(.leftArrow) {
                        guard query.isEmpty, level != nil else { return .ignored }
                        back()
                        return .handled
                    }
            }
            .padding(14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                            LauncherRow(
                                item: item,
                                breadcrumb: query.isEmpty ? nil : model.menu.path(to: item.parentID ?? "").joined(separator: " › "),
                                isSelected: index == selection,
                                isChecked: model.checks[item.id] == true,
                                hasChildren: model.hasChildren(item)
                            )
                            .id(item.id)
                            .onTapGesture {
                                selection = index
                                activateSelection()
                            }
                        }
                        if rows.isEmpty {
                            Text(query.isEmpty ? "Nothing here." : "No match for “\(query)”.")
                                .foregroundStyle(.secondary)
                                .padding(20)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { _, newValue in
                    guard newValue >= 0, newValue < rows.count else { return }
                    proxy.scrollTo(rows[newValue].id)
                }
            }

            if let error = model.menuError ?? model.lastError {
                Divider()
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(8)
            }
        }
        .frame(width: 580, height: 420)
        .onAppear(perform: reset)
        .onChange(of: model.launcherSession) { _, _ in reset() }
        .onChange(of: query) { _, _ in selection = 0 }
        // Re-check guards whenever the level changes or the launcher is shown again (the panel is reused).
        .task(id: GuardKey(level: level, session: model.launcherSession)) {
            await model.evaluateGuards(model.menu.children(of: level))
        }
        .task(id: query) {
            guard !query.isEmpty else { return }
            await model.evaluateGuards(model.menu.search(query))
        }
    }

    private struct GuardKey: Hashable {
        let level: String?
        let session: Int
    }

    private func reset() {
        query = ""
        level = model.launcherStartLevel
        selection = 0
        searchFocused = true
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = (selection + delta + rows.count) % rows.count
    }

    private func back() {
        if !query.isEmpty {
            query = ""
        } else if let current = level {
            level = model.menu.item(current)?.parentID
            selection = 0
        } else {
            onClose()
        }
    }

    private func activateSelection() {
        let current = rows
        guard selection >= 0, selection < current.count else { return }
        let item = current[selection]
        if item.action != nil {
            model.run(item)
            onClose()
        } else if model.hasChildren(item) {
            level = item.id
            query = ""
            selection = 0
        }
    }
}

struct LauncherRow: View {
    let item: MenuItem
    let breadcrumb: String?
    let isSelected: Bool
    let isChecked: Bool
    let hasChildren: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon ?? "circle")
                .frame(width: 22)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                if let breadcrumb, !breadcrumb.isEmpty {
                    Text(breadcrumb)
                        .font(.caption)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                }
            }
            Spacer()
            if isChecked {
                Image(systemName: "checkmark")
            }
            if hasChildren {
                Image(systemName: "chevron.right")
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.primary))
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear))
        )
    }
}

/// Owns the launcher panel: centered on the screen with the pointer, closes when it loses focus.
@MainActor
public final class LauncherController {
    private let model: SummonModel
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?

    public init(model: SummonModel) {
        self.model = model
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func toggle() {
        if isVisible { hide() } else { show(startAt: nil) }
    }

    public func show(startAt level: String?) {
        model.prepareLauncher(startAt: level)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - visible.height * 0.18)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let view = LauncherView(model: model, onClose: { [weak self] in self?.hide() })
        panel.contentView = NSHostingView(rootView: view)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hide()
            }
        }
        return panel
    }
}

#Preview("Launcher") {
    LauncherView(model: .preview(), onClose: {})
}
