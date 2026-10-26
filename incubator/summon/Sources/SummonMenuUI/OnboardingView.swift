import AppKit
import SummonCore
import SwiftUI

/// The first-run setup window (docs/ux-surfaces/06-onboarding.md): 640 × 440, centered, close only. Three steps:
/// the agent, Accessibility, then where Summon lives. Closing it skips setup and Summon still works; Settings ›
/// General › Show Welcome Again and `summon://welcome` bring it back. Summon shows in the Dock while it is open, so
/// the window isn't lost behind System Settings.
public struct OnboardingView: View {
    @Bindable var model: SummonModel
    /// Done: close, then open the menu bar panel so people see where Summon lives.
    let onFinish: @MainActor () -> Void
    @State private var flow = OnboardingFlow()
    @State private var forward = true
    @State private var wasAccessory = false
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let windowID = "onboarding"
    public static let title = "Welcome to Summon"

    public init(model: SummonModel, onFinish: @escaping @MainActor () -> Void = {}) {
        self.model = model
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
                Button(flow.isLast ? "Done" : "Continue") { move(forward: true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 640, height: 440)
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

    @ViewBuilder private var page: some View {
        switch flow.step {
        case .agent: OnboardingAgentPage(model: model)
        case .accessibility: OnboardingAccessibilityPage(model: model)
        case .ready: OnboardingReadyPage(shortcut: model.globalMenuShortcut.displayString)
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

/// Step 1: what Summon is, and which agent it uses (installed agents only; with none, how to install one).
struct OnboardingAgentPage: View {
    @Bindable var model: SummonModel

    private var installed: [Agent] { AgentRegistry.all.filter { model.installedAgentIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(OnboardingView.title).font(.largeTitle.bold())
                Text("Summon brings your coding agent to the whole Mac: ask about what's on screen, find out why an app crashed, make small apps. Choose the agent it uses.")
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
                Picker("Agent", selection: Binding(
                    get: { model.defaultAgent?.id ?? "" },
                    set: { if !$0.isEmpty { model.setDefaultAgent($0) } }
                )) {
                    ForEach(installed, id: \.id) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("You can change it later in Settings › Agents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Step 2: why Summon asks for Accessibility, then a live status. Optional: Continue moves on either way.
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
                }
            }
            .padding(14)
            .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            Text("Without it, the agent still sees which app and web page you're on.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The switch is flipped in System Settings: check again every second while this page shows.
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Step 3: where Summon lives (HIG Menu bar extras: show people the extra during setup).
struct OnboardingReadyPage: View {
    let shortcut: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce.up, options: .repeat(3), isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text("Summon Lives in the Menu Bar").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Click its icon at the top of the screen, or press \(shortcut) in any app. Then type to find anything Summon can do.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(shortcut)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.quinary, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Shortcut \(shortcut)")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
