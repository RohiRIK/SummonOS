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

    /// Home: Ask Agent, Make Something, My Apps and one status line; everything else is found by typing.
    private var isHome: Bool { level == nil && query.isEmpty }

    /// The menu level's visible children (at home only `PanelLayout.homeItems`), or search results across the whole
    /// tree (hidden entries excluded).
    private var rows: [MenuItem] {
        guard query.isEmpty else { return model.menu.search(query).filter { model.visibility[$0.id] != false } }
        let children = model.visibleChildren(of: level)
        return level == nil ? children.filter { PanelLayout.homeItems.contains($0.id) } : children
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
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    /// One status line, only when something is wrong (owner: no per-crash list in the panel). Crashes open
    /// Activity's problems, where each has Diagnose; setup problems go to the agent (`summon fix`).
    @ViewBuilder private var attentionRow: some View {
        let attention = PanelAttention(reports: model.panelProblems, doctor: model.doctorReport)
        if let summary = attention.summary {
            MenuRow(title: summary, systemImage: "exclamationmark.triangle.fill", shortcut: nil) {
                if attention.crashes.isEmpty {
                    actions.finish()
                    model.fixWithAI()
                } else {
                    activity.filter = .problems
                    activity.selection = nil
                    actions.openActivity()
                }
            }
        }
    }

    private var askAgentRow: some View {
        MenuRow(title: "Ask Agent", systemImage: "sparkles", shortcut: model.panelAgentShortcut.displayString) {
            actions.finish()
            model.askAgentAboutScreen()
        }
        .keyboardShortcut(model.panelAgentShortcut.keyEquivalent, modifiers: model.panelAgentShortcut.eventModifiers)
        .disabled(model.defaultAgent == nil || !model.agentInstalled)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            // Always visible (owner, 2026-10-26), so people know they can type.
            search
            if isHome { askAgentRow }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                MenuTreeRow(item: item,
                            breadcrumb: query.isEmpty ? nil : model.menu.path(to: item.parentID ?? "").joined(separator: " › "),
                            isSelected: index == selection,
                            isChecked: model.checks[item.id] == true,
                            hasChildren: model.hasChildren(item),
                            health: model.health(for: item)) {
                    selection = index
                    activateSelection()
                }
                .id(item.id)
            }
            if rows.isEmpty && !isHome {
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
            if isHome { attentionRow }
            if isHome, let update = model.availableUpdate {
                MenuRow(title: model.isUpdating ? "Updating Summon…" : "Summon \(update.release.version) available · Update",
                        systemImage: "arrow.down.circle", shortcut: nil) {
                    model.installUpdate()
                }
                .disabled(model.isUpdating)
            }
            if let offer = model.undoOffer, isHome {
                MenuRow(title: offer.title, systemImage: "arrow.uturn.backward", shortcut: nil) {
                    actions.finish()
                    model.confirmUndo(offer)
                }
            }
            if panel.fixtureRows > 0 {
                PanelDivider()
                ForEach(0..<panel.fixtureRows, id: \.self) { row in
                    MenuRow(title: "Fixture row \(row + 1)", systemImage: "square.dashed", shortcut: nil) {}
                }
            }

            // Footer per AGENTS.md; the right-click menu has the same two items (decision 5).
            PanelDivider()
            MenuRow(title: "Activity…", systemImage: nil, shortcut: nil) {
                activity.selection = nil
                actions.openActivity()
            }
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
            if level != nil {
                Button(action: back) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                        Text(model.menu.path(to: level!).joined(separator: " › "))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back (click, ←, or Delete)")
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            TextField(level == nil ? "Search Summon…" : "Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search Summon")
                .onSubmit(activateFromKeyboard)
                .onKeyPress(.escape) {
                    if level != nil {
                        back()
                        return .handled
                    }
                    actions.escape()
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    if model.panelAgentShortcut.matches(press) {
                        guard model.defaultAgent != nil && model.agentInstalled else { return .ignored }
                        actions.finish()
                        model.askAgentAboutScreen()
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
                .onKeyPress(.delete) {
                    guard query.isEmpty, level != nil else { return .ignored }
                    back()
                    return .handled
                }
        }
        .font(.body)
        .padding(.horizontal, 8)
        .frame(height: 28)
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
        query = ""
        if let current = level {
            if let dot = current.lastIndex(of: ".") {
                level = String(current[..<dot])
            } else {
                level = nil
            }
        }
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
            // The Summon mark (the app icon), not a stock symbol.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
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
    @ViewBuilder private var agentLine: some View {
        if let agent = model.defaultAgent {
            if !model.agentInstalled {
                Text("\(agent.name) is not installed")
            } else if refreshedSession == panel.session, let since = activity.status?.agent.since,
                      activity.status?.agent.running == true {
                // Coarse on purpose ("running 3h"): status, not a stopwatch.
                let ago = PanelClock.ago(since)
                Text(ago == "now" ? "\(agent.name) · running" : "\(agent.name) · running \(ago)")
            } else {
                Text(agent.name)
            }
        } else if model.installedAgentIDs.isEmpty {
            Text("No agent installed")
        } else {
            // Picking one here, not in Settings: Ask Agent works right away.
            Menu("Choose an agent") {
                ForEach(AgentRegistry.all.filter { model.installedAgentIDs.contains($0.id) }, id: \.id) { agent in
                    Button(agent.name) { model.setDefaultAgent(agent.id) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
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
    var health: ItemHealth? = nil
    let action: () -> Void

    var body: some View {
        PanelRow(isSelected: isSelected, hoverHighlights: false, action: action) {
            Image(systemName: item.icon ?? "circle")
                .frame(width: 16)
                .foregroundStyle(health?.level == .error ? Color.red : (health?.level == .warning ? Color.orange : Color.secondary))
            Text(item.label)
            if let breadcrumb, !breadcrumb.isEmpty {
                Text(breadcrumb).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            if let health {
                Circle()
                    .fill(health.level == .healthy ? Color.green : (health.level == .warning ? Color.orange : Color.red))
                    .frame(width: 6, height: 6)
            }
            if isChecked {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
            if hasChildren {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        // The health dot is color only; VoiceOver hears its badge ("Healthy", "2 warnings") instead.
        .accessibilityValue(health?.badge ?? "")
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

/// Liquid Glass behind the panel on macOS 26 (system-menu look, never on rows), the menu material before.
struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26, *) {
            return NSGlassEffectView()
        }
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
