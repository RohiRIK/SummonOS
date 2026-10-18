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
                Image(systemName: level == nil ? "magnifyingglass" : "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                if let level {
                    Text(model.menu.path(to: level).joined(separator: " › "))
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                TextField(level == nil ? "Search Summon…" : "Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .light))
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
            .padding(.horizontal, 18)
            .frame(height: 56)

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
                    .padding(8)
                }
                .scrollIndicators(.never)
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

            Divider()
            footer
        }
        .frame(width: 620, height: Self.height)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
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

    static let height: CGFloat = 450

    /// Raycast-style action bar: where you are on the left, the keys that work here on the right.
    private var footer: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").foregroundStyle(.tint)
            Text("Summon").foregroundStyle(.secondary)
            Spacer()
            KeyHint(key: "↵", label: rows.indices.contains(selection) && model.hasChildren(rows[selection]) ? "Open" : "Run")
            if level != nil || !query.isEmpty { KeyHint(key: "←", label: "Back") }
            KeyHint(key: "esc", label: "Close")
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: 34)
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
        HStack(spacing: 12) {
            // Icon tile: tinted when selected, quiet otherwise.
            Image(systemName: item.icon ?? "circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                )
            Text(item.label)
            if let breadcrumb, !breadcrumb.isEmpty {
                Text(breadcrumb)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if isChecked {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
            if hasChildren {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(HierarchicalShapeStyle.quaternary) : AnyShapeStyle(Color.clear))
        )
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text(key)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary))
        }
    }
}

/// Behind-window blur, so the launcher is translucent like the menu bar panel.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Borderless panels refuse key status by default; the search field needs it.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: LauncherView.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
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
