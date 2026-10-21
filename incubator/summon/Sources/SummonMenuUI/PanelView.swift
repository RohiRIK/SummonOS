import AppKit
import SummonCore
import SwiftUI

/// The menu bar panel: the Summon Menu (search field + menu tree, formerly the launcher window) above the app's job
/// (ask the agent, Activity), with the Settings…/Quit footer (AGENTS.md). Hosted once by `PanelController` in a
/// nonactivating `StatusPanel`; it stays one SwiftUI view and keeps updating while open (spec v1.5, E1–E5).
/// Every row that does something calls `actions.finish` so the panel closes (D3).
public struct PanelView: View {
    let model: SummonModel
    let activity: ActivityModel
    let panel: PanelState
    let actions: PanelActions

    @State private var query = ""
    @State private var level: String?
    @State private var selection = 0
    @State private var contentHeight: CGFloat = 0
    /// E5: the `PanelState.session` whose first Activity refresh has finished. Until it matches, the agent line
    /// doesn't show the previous open's "running" state.
    @State private var refreshedSession = 0
    @FocusState private var searchFocused: Bool

    public init(model: SummonModel, activity: ActivityModel, panel: PanelState, actions: PanelActions) {
        self.model = model
        self.activity = activity
        self.panel = panel
        self.actions = actions
    }

    /// The menu level's visible children, or search results across the whole tree (hidden entries excluded).
    private var rows: [MenuItem] {
        query.isEmpty ? model.visibleChildren(of: level) : model.menu.search(query).filter { model.visibility[$0.id] != false }
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        contentHeight = height
                        // E3/E4: the controller sets the panel frame once, top edge pinned.
                        actions.resize(max(1, min(height, panel.maxHeight)))
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selection) { _, newValue in
                guard rows.indices.contains(newValue) else { return }
                proxy.scrollTo(rows[newValue].id)
            }
        }
        // E3/E4: as tall as the content, capped at the screen's visible height; past that it scrolls inside.
        .frame(width: PanelConfig.width, height: max(1, min(contentHeight, panel.maxHeight)))
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Summon")
        // A1/E5: every open (and `summon://menu/<id>`) starts clean at its level. Focus comes only from
        // `focusRequest`, which URL/CLI opens don't bump.
        .onAppear(perform: reset)
        .onChange(of: model.launcherSession) { _, _ in reset() }
        // A1/A2/G1: focus once the panel is key (the controller bumps this after makeKeyAndOrderFront).
        .onChange(of: panel.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        // Re-check `when`/`checked` guards whenever the level changes or the panel opens again.
        .task(id: GuardKey(level: level, session: model.launcherSession)) {
            await model.evaluateGuards(model.menu.children(of: level))
        }
        .task(id: query) {
            guard !query.isEmpty else { return }
            await model.evaluateGuards(model.menu.search(query))
        }
        // E1/E5: refresh at once on open, then every 1 s while open; cancelled on close.
        .task(id: panel.isOpen) {
            guard panel.isOpen else { return }
            model.reloadProjects()
            let session = panel.session
            guard activity.live else {
                refreshedSession = session
                return
            }
            while !Task.isCancelled {
                await activity.refresh()
                if refreshedSession != session { refreshedSession = session }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            search
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                MenuTreeRow(item: item,
                            breadcrumb: query.isEmpty ? nil : model.menu.path(to: item.parentID ?? "").joined(separator: " › "),
                            isSelected: index == selection,
                            isChecked: model.checks[item.id] == true,
                            hasChildren: model.hasChildren(item)) {
                    selection = index
                    activateSelection()
                }
                .id(item.id)
            }
            if rows.isEmpty {
                Text(query.isEmpty ? "Nothing here." : "No match for “\(query)”.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            if let error = model.menuError ?? model.lastError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
            PanelDivider()
            MenuRow(title: "Ask Agent", systemImage: "sparkles", shortcut: model.panelAgentShortcut.displayString) {
                actions.finish()
                model.askAgent()
            }
            .keyboardShortcut(model.panelAgentShortcut.keyEquivalent, modifiers: model.panelAgentShortcut.eventModifiers)
            .disabled(model.defaultAgent == nil || !model.agentInstalled)
            MenuRow(title: "Activity…", systemImage: "list.bullet.rectangle", shortcut: nil) {
                actions.finish()
                activity.selection = nil
                // Hosted outside any SwiftUI scene: the always-alive opener window opens Activity.
                activity.requestOpen()
            }
            if panel.fixtureRows > 0 {
                PanelDivider()
                ForEach(0..<panel.fixtureRows, id: \.self) { row in
                    MenuRow(title: "Fixture row \(row + 1)", systemImage: "square.dashed", shortcut: nil) {}
                }
            }

            // Footer per AGENTS.md; the right-click menu has the same two items (decision 5).
            PanelDivider()
            MenuRow(title: "Settings…", systemImage: nil, shortcut: "⌘,") {
                actions.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit Summon", systemImage: nil, shortcut: "⌘Q") {
                actions.quit()
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(6)
    }

    /// A2/A4: typing stays in the panel. ↑↓ select, → or Return opens a submenu, ← goes back, Return runs, Esc closes.
    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: level == nil ? "magnifyingglass" : "chevron.left")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            if let level {
                Text(model.menu.path(to: level).joined(separator: " › "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            TextField(level == nil ? "Search Summon…" : "Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search Summon")
                .onSubmit(activateFromKeyboard)
                .onKeyPress(.escape) { actions.escape(); return .handled }
                .onKeyPress(phases: .down) { press in
                    if model.panelAgentShortcut.matches(press) {
                        guard model.defaultAgent != nil && model.agentInstalled else { return .ignored }
                        actions.finish()
                        model.askAgent()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.rightArrow) {
                    guard query.isEmpty else { return .ignored }
                    activateFromKeyboard()
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    guard query.isEmpty, level != nil else { return .ignored }
                    back()
                    return .handled
                }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }

    private struct GuardKey: Hashable {
        let level: String?
        let session: Int
    }

    private func reset() {
        query = ""
        level = model.launcherStartLevel
        selection = 0
        model.reloadProjects()
    }

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = (selection + delta + rows.count) % rows.count
    }

    private func back() {
        level = level.flatMap { model.menu.item($0)?.parentID }
        selection = 0
    }

    /// Return / → : ignored for ~300 ms after a hotkey or URL/CLI open (`PanelOpenGuard`), so a keystroke meant for
    /// another app can't run an entry. Clicks go straight to `activateSelection`.
    private func activateFromKeyboard() {
        guard actions.acceptsReturn() else { return }
        activateSelection()
    }

    private func activateSelection() {
        let current = rows
        guard current.indices.contains(selection) else { return }
        let item = current[selection]
        if item.action != nil {
            actions.finish()
            model.run(item)
        } else if model.hasChildren(item) {
            level = item.id
            query = ""
            selection = 0
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Summon").font(.headline)
                agentLine
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// E5: until this open's first refresh lands, only the agent's name shows (no stale "running" from last time).
    /// E1: a running agent shows elapsed mm:ss, ticking every second in place while the panel is open.
    @ViewBuilder private var agentLine: some View {
        if let agent = model.defaultAgent {
            if !model.agentInstalled {
                Text("\(agent.name) is not installed")
            } else if refreshedSession == panel.session,
                      let since = activity.status?.agent.since, activity.status?.agent.running == true {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text("\(agent.name) · running \(PanelClock.elapsed(from: since, to: context.date))")
                        .monospacedDigit()
                }
            } else {
                Text(agent.name)
            }
        } else {
            Text("No default agent: choose one in Settings")
        }
    }
}

/// The one row chrome the panel uses (Max's review: no near-duplicate rows): fixed padding and height, a rounded
/// highlight when `isSelected` (keyboard selection in the menu tree) or, if `hoverHighlights`, under the pointer.
struct PanelRow<Content: View>: View {
    var isSelected = false
    var hoverHighlights = true
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8, content: content)
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(highlighted ? AnyShapeStyle(HierarchicalShapeStyle.quaternary) : AnyShapeStyle(Color.clear))
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var highlighted: Bool {
        isSelected || (hoverHighlights && hovering && isEnabled)
    }
}

/// One Summon Menu entry in the panel: icon, label, breadcrumb when searching, check mark, submenu chevron.
struct MenuTreeRow: View {
    let item: MenuItem
    let breadcrumb: String?
    let isSelected: Bool
    let isChecked: Bool
    let hasChildren: Bool
    let action: () -> Void

    var body: some View {
        PanelRow(isSelected: isSelected, hoverHighlights: false, action: action) {
            Image(systemName: item.icon ?? "circle")
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(item.label)
            if let breadcrumb, !breadcrumb.isEmpty {
                Text(breadcrumb).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            if isChecked {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
            if hasChildren {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// A command row styled like a system menu item: hover highlight, trailing key hint in tertiary.
struct MenuRow: View {
    let title: String
    let systemImage: String?
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        PanelRow(action: action) {
            if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
            }
            Text(title)
            Spacer()
            if let shortcut {
                Text(shortcut).foregroundStyle(.tertiary)
            }
        }
    }
}

struct PanelDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 3)
    }
}

#Preview("Panel") {
    let activity = ActivityModel.preview()
    return PanelView(model: activity.summon, activity: activity, panel: .preview(), actions: .preview)
}
