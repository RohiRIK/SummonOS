import AppKit
import SummonCore
import SwiftUI

/// The first-run setup window (docs/ux-surfaces/06-onboarding.md): 720 × 480, centered, close only. Four steps:
/// what Summon does, the agent, Accessibility, then where Summon lives (with a live "try it"). Closing it skips setup
/// and Summon still works; Settings › General › Show Welcome Again and `summon://welcome` bring it back. Summon shows
/// in the Dock while it is open, so the window isn't lost behind System Settings.
public struct OnboardingView: View {
    @Bindable var model: SummonModel
    /// The menu bar panel, so the last step can see it open and whether its icon has room. Nil in previews.
    let panel: PanelController?
    /// Done: close, then open the menu bar panel so people see where Summon lives.
    let onFinish: @MainActor () -> Void
    @State private var flow = OnboardingFlow()
    @State private var forward = true
    @State private var wasAccessory = false
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let windowID = "onboarding"
    public static let title = "Welcome to Summon"

    public init(model: SummonModel, panel: PanelController? = nil, onFinish: @escaping @MainActor () -> Void = {}) {
        self.model = model
        self.panel = panel
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page.id(flow.step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Divider()
            HStack {
                OnboardingStepDots(count: flow.steps.count, current: flow.index)
                Spacer()
                if !flow.isFirst {
                    Button("Back") { move(forward: false) }
                }
                // HIG Privacy: "Skip" is fine where the step only sends people to System Settings.
                if skipping {
                    Button("Skip") { move(forward: true) }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                } else {
                    Button(primaryTitle) { move(forward: true) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 720, height: 480)
        .closeOnlyWindow()
        .onAppear {
            wasAccessory = NSApp.activationPolicy() == .accessory
            if wasAccessory { NSApp.setActivationPolicy(.regular) }
            NSApp.activate()
        }
        .onDisappear {
            // Closing is skipping: it doesn't come back on its own.
            UserDefaults.standard.set(true, forKey: OnboardingFlow.completedKey)
            if wasAccessory { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private var skipping: Bool { flow.step == .accessibility && !model.accessibilityGranted }

    private var primaryTitle: String {
        if flow.isFirst { return "Get Started" }
        return flow.isLast ? "Done" : "Continue"
    }

    @ViewBuilder private var page: some View {
        switch flow.step {
        case .welcome: OnboardingWelcomePage(shortcut: model.globalMenuShortcut.displayString)
        case .agent: OnboardingAgentPage(model: model)
        case .accessibility: OnboardingAccessibilityPage(model: model)
        case .ready: OnboardingReadyPage(shortcut: model.globalMenuShortcut.displayString, panel: panel)
        }
    }

    private func move(forward: Bool) {
        self.forward = forward
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            if forward {
                if !flow.next() { finish() }
            } else {
                flow.back()
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: OnboardingFlow.completedKey)
        dismissWindow(id: Self.windowID)
        // After the window has gone and Summon is an accessory app again, so the panel opens under the icon.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            onFinish()
        }
    }
}

/// Step 1: a short brand moment (HIG Onboarding allows a brief splash), then what Summon is for, one line each.
struct OnboardingWelcomePage: View {
    let shortcut: String
    /// Bundled by scripts/bundle.sh from design/brand/banner.png; previews fall back to a plain header.
    private static let banner = Bundle.main.image(forResource: "banner")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let banner = Self.banner {
                    Image(nsImage: banner).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.indigo.gradient)
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 18) {
                Text(OnboardingView.title).font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingFeatureRow(symbol: "text.viewfinder", title: "Ask about your screen",
                                         detail: "Press \(shortcut) in any app; your coding agent sees what you're looking at.")
                    OnboardingFeatureRow(symbol: "stethoscope", title: "Find out why an app crashed",
                                         detail: "Summon notices crashes and hands the report to your agent.")
                    OnboardingFeatureRow(symbol: "hammer", title: "Make small Mac apps",
                                         detail: "Describe one; your agent builds it from Summon's native templates.")
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct OnboardingFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Step 2: which agent Summon starts, and whether it is logged in (installed agents only; with none, how to install
/// one). Same account check as Settings › Agents.
struct OnboardingAgentPage: View {
    @Bindable var model: SummonModel

    private var installed: [Agent] { AgentRegistry.all.filter { model.installedAgentIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Your Agent").font(.largeTitle.bold())
                Text("Summon starts this coding agent for you. It needs to be logged in to its account.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if installed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No coding agent found", systemImage: "exclamationmark.circle")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Install one in Terminal, then check again. For Claude Code:")
                        .foregroundStyle(.secondary)
                    Text(AgentRegistry.all.first?.installHint ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Check Again") { model.reload() }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(installed, id: \.id) { agent in
                            OnboardingAgentRow(model: model, agent: agent)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                Text("You can change it later in Settings › Agents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            for agent in installed where model.agentStatus[agent.id] == nil {
                await model.checkAgent(agent.id)
            }
            // "Log In…" finishes in a terminal: check the ones still logged out again while this page shows.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                for agent in installed where model.agentStatus[agent.id]?.login.loggedIn == false {
                    await model.checkAgent(agent.id)
                }
            }
        }
    }
}

struct OnboardingAgentRow: View {
    @Bindable var model: SummonModel
    let agent: Agent

    private var selected: Bool { model.defaultAgent?.id == agent.id }

    var body: some View {
        HStack(spacing: 12) {
            AgentBrandIcon(agentId: agent.id, size: 22)
                .foregroundStyle(.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name).font(.headline)
                login
            }
            Spacer()
            if model.agentStatus[agent.id]?.login.loggedIn == false {
                Button("Log In…") { model.logIn(agent.id) }
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(selected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quinary),
                    in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { model.setDefaultAgent(agent.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.setDefaultAgent(agent.id) }
    }

    @ViewBuilder private var login: some View {
        if model.checkingAgents.contains(agent.id) {
            Text("Checking account…").foregroundStyle(.secondary)
        } else {
            switch model.agentStatus[agent.id]?.login.loggedIn {
            case true?:
                Label(["Connected", model.agentStatus[agent.id]?.login.detail].compactMap { $0 }.joined(separator: " · "),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case false?:
                Label("Not logged in", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            case nil:
                Text("Account unknown").foregroundStyle(.secondary)
            }
        }
    }
}

/// Step 3: why Summon asks for Accessibility, then a live status. Optional: Skip moves on.
struct OnboardingAccessibilityPage: View {
    @Bindable var model: SummonModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let Summon Read the Screen").font(.largeTitle.bold())
            Text("When you ask the agent about your screen, Summon passes it the selected text and the front window's title. macOS asks you to allow this under Accessibility. Summon never types or clicks for you.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Image(systemName: "accessibility")
                    .font(.title2)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility").font(.headline)
                    // Words and a symbol, never color alone.
                    Label(model.accessibilityGranted ? "Allowed" : "Not allowed yet",
                          systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                }
                Spacer()
                if !model.accessibilityGranted {
                    Button("Open System Settings") { model.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            // Each new build is a new app to macOS, so an old switch can look on and not count (requestAccessibility).
            Text(model.accessibilityGranted
                 ? "Without it, the agent still sees which app and web page you're on."
                 : "Switch already on? Summon was updated. Click Open System Settings and turn Summon on again.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The switch is flipped in System Settings: check again every second while this page shows.
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Step 4: where Summon lives (HIG Menu bar extras: show people the extra during setup), taught by doing: the
/// shortcut card turns green once the panel opens. Warns when the menu bar has no room for the icon (research §3.6).
struct OnboardingReadyPage: View {
    let shortcut: String
    let panel: PanelController?
    @State private var opensAtStart: Int?
    @State private var iconHidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var triedIt: Bool {
        guard let panel, let opensAtStart else { return false }
        return panel.state.session > opensAtStart
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce.up, options: .repeat(3), isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text("Summon Lives in the Menu Bar").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Click its icon at the top of the screen, or press the shortcut in any app. Then type to find anything Summon can do.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text(shortcut)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.background, in: .rect(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Shortcut \(shortcut)")
                if triedIt {
                    Label("That's it. Press it again or Esc to close.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Try it now").foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            if iconHidden {
                Label("Your menu bar is full, so the Summon icon is hidden (behind the notch or another app). The shortcut always works; ⌘-drag other icons out of the menu bar to make room.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .default, value: triedIt)
        .task {
            opensAtStart = panel?.state.session
            while !Task.isCancelled {
                iconHidden = panel.map { !$0.isStatusItemVisible } ?? false
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct OnboardingStepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

#Preview("Welcome") {
    OnboardingView(model: .preview())
}
