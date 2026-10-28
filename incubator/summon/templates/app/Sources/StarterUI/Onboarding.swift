import AppKit
import StarterCore
import SwiftUI

/// A macOS permission the setup can ask for. Both are granted in System Settings, with no system alert, so their
/// cards may offer "Skip for Now" (HIG Privacy: only a step that opens a system alert must have one button).
public enum Permission: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case screenRecording

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    /// The documented checks; neither prompts.
    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    var settingsURL: URL? {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}

/// What this app's setup says. Edit it for your app; leave `permissions` empty unless the app can't do its job
/// without one (the starter needs none, so its setup is two steps).
public enum StarterOnboarding {
    public static let permissions: [Permission] = []
    static let features = [
        Feature(symbol: "bolt", title: "Fast", text: "Opens at once and works offline."),
        Feature(symbol: "keyboard", title: "Keyboard first", text: "Every action has a shortcut."),
        Feature(symbol: "paintpalette", title: "Follows your theme", text: "Picks up the Summon theme's accent."),
    ]

    struct Feature: Sendable {
        let symbol: String
        let title: String
        let text: String
    }
}

/// The first-run window: 640 × 440, centered, close only. Closing it skips setup and the app still works;
/// Settings › Show Welcome Again brings it back. An agent app shows in the Dock while it is open, so it isn't lost
/// behind System Settings, and leaves the Dock when it closes.
public struct OnboardingView: View {
    private let readyTitle: String
    private let readyText: String
    private let readySymbol: String
    @State private var flow = OnboardingFlow(needsPermissions: !StarterOnboarding.permissions.isEmpty)
    @State private var forward = true
    @State private var wasAgent = false
    @AppStorage(OnboardingFlow.completedKey) private var completed = false
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let windowID = "onboarding"

    /// `ready…` is the last step: where the app lives and what to try first.
    public init(readyTitle: String, readyText: String, readySymbol: String) {
        self.readyTitle = readyTitle
        self.readyText = readyText
        self.readySymbol = readySymbol
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
                StepDots(count: flow.steps.count, current: flow.index)
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
            wasAgent = NSApp.activationPolicy() == .accessory
            if wasAgent { NSApp.setActivationPolicy(.regular) }
            NSApp.activate()
        }
        .onDisappear {
            completed = true // closing is skipping
            if wasAgent { NSApp.setActivationPolicy(.accessory) }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch flow.step {
        case .welcome:
            WelcomePage()
        case .permissions:
            PermissionsPage(permissions: StarterOnboarding.permissions)
        case .ready:
            ReadyPage(title: readyTitle, text: readyText, symbol: readySymbol)
        }
    }

    private func move(forward: Bool) {
        self.forward = forward
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            if forward {
                if !flow.next() {
                    completed = true
                    dismissWindow(id: OnboardingView.windowID)
                }
            } else {
                flow.back()
            }
        }
    }
}

struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Starter").font(.largeTitle.bold())
                Text("Write the app's one job here, in a sentence.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(StarterOnboarding.features, id: \.title) { feature in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(feature.title).font(.headline)
                            Text(feature.text).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: feature.symbol).foregroundStyle(.tint).frame(width: 24)
                    }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One card per permission, with its live status (color and words, never color alone) and a deep link.
struct PermissionsPage: View {
    let permissions: [Permission]
    @State private var granted: Set<Permission> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allow Access").font(.largeTitle.bold())
            Text("Starter needs this to do its job. Turn it on in System Settings, then come back.")
                .font(.title3).foregroundStyle(.secondary)
            ForEach(permissions) { permission in
                PermissionCard(permission: permission, isGranted: granted.contains(permission))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The switch is flipped in System Settings: check when the user comes back to this app,
        // plus a slow loop as a backstop, only while this page shows.
        .task {
            while !Task.isCancelled {
                granted = Set(permissions.filter(\.isGranted))
                try? await Task.sleep(for: .seconds(3), tolerance: .seconds(1))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = Set(permissions.filter(\.isGranted))
        }
    }
}

struct PermissionCard: View {
    let permission: Permission
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.title2)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.headline)
                Label(isGranted ? "Allowed" : "Not allowed yet", systemImage: isGranted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(isGranted ? .green : .orange)
            }
            Spacer()
            if !isGranted, let url = permission.settingsURL {
                Button("Open System Settings") { NSWorkspace.shared.open(url) }
            }
        }
        .padding(14)
        .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ReadyPage: View {
    let title: String
    let text: String
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce.up, options: .repeat(3), isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StepDots: View {
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

extension View {
    /// Opens the setup window once, on the first launch. Put it on a view that appears at launch.
    public func showsOnboardingOnFirstLaunch() -> some View {
        modifier(FirstLaunchOnboarding())
    }
}

private struct FirstLaunchOnboarding: ViewModifier {
    @AppStorage(OnboardingFlow.completedKey) private var completed = false
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            // Not while drawing screenshots or in previews: only the real app at launch.
            guard !completed, !CommandLine.arguments.contains("--screenshot") else { return }
            openWindow(id: OnboardingView.windowID)
        }
    }
}

/// Settings › General: brings the setup back (HIG Onboarding: let people see it again).
struct ShowWelcomeButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LabeledContent("Welcome") {
            Button("Show Again") { openWindow(id: OnboardingView.windowID) }
        }
    }
}

#Preview("Welcome") {
    OnboardingView(readyTitle: "Starter lives in the menu bar", readyText: "Click its icon at the top of the screen.",
                   readySymbol: "arrow.up")
}
