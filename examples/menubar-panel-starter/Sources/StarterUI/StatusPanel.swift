import AppKit
import SwiftUI

/// What the panel content can ask the controller to do.
public struct PanelActions {
    public var close: () -> Void
    public var openSettings: () -> Void
    public var quit: () -> Void

    public init(close: @escaping () -> Void, openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.close = close
        self.openSettings = openSettings
        self.quit = quit
    }

    static var preview: PanelActions { PanelActions(close: {}, openSettings: {}, quit: {}) }
}

/// A borderless, nonactivating panel: it becomes key (takes keystrokes) without activating the app, so the
/// frontmost app keeps its menu bar and focus.
@MainActor
final class StatusPanel: NSPanel {
    var onEscape: (() -> Void)?

    /// The style mask is set at creation: changing `.nonactivatingPanel` later is unreliable.
    static func make() -> StatusPanel {
        let panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 160),
                                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar // above fullscreen apps
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false // the app is usually not active; the controller closes the panel
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }

    // A borderless panel refuses key status by default, so its buttons' shortcuts would never fire.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Shows and hides the panel under the status item. Opens from a click or from code (`open()`, `toggle()`, for
/// a hotkey or URL); closes on Esc, a click elsewhere (the panel loses key), a Space change, or an action.
@MainActor
public final class PanelController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = StatusPanel.make()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public var isOpen: Bool { panel.isVisible }

    public init<Content: View>(image: NSImage?, openSettings: @escaping () -> Void,
                               @ViewBuilder content: (PanelActions) -> Content) {
        super.init()
        let actions = PanelActions(
            close: { [weak self] in self?.close() },
            openSettings: { [weak self] in
                self?.close()
                openSettings()
            },
            quit: { NSApp.terminate(nil) }
        )
        let host = NSHostingView(rootView: content(actions)
            .background(.regularMaterial, in: .rect(cornerRadius: 12)))
        host.sizingOptions = [.preferredContentSize] // the panel follows SwiftUI's ideal size
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.close() }

        if let button = statusItem.button {
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
        }
    }

    public func toggle() { isOpen ? close() : open() }

    /// Idempotent: opening an open panel does nothing.
    public func open() {
        guard !isOpen, let button = statusItem.button else { return }
        place(under: button)
        panel.makeKeyAndOrderFront(nil) // nonactivating: key without activating the app
        button.highlight(true)
        // After the current event: the status button's mouse-up tracking can reset the highlight.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen else { return }
            self.statusItem.button?.highlight(true)
        }
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification, object: panel)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
    }

    /// Idempotent: closing a closed panel does nothing. Every close removes its observers.
    public func close() {
        guard isOpen else { return }
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        statusItem.button?.highlight(false)
        panel.orderOut(nil)
    }

    /// A live label: the icon alone when `title` is nil, else icon and title in monospaced digits so the
    /// item's width doesn't jitter as the number changes.
    public func setLabel(title: String?, accessibilityLabel: String) {
        guard let button = statusItem.button else { return }
        button.title = title ?? ""
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.setAccessibilityLabel(accessibilityLabel)
    }

    @objc private func statusItemClicked() { toggle() }

    /// Under the status item on the screen whose menu bar was clicked, clamped 8 pt inside the visible frame.
    private func place(under button: NSStatusBarButton) {
        guard let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let visible = screen.visibleFrame
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = anchor.minY - size.height - 4
        panel.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        observers.append((center, token))
    }
}

/// Turns the model's Settings request into SwiftUI's openSettings(), which needs a scene. Lives in an
/// invisible, always-open window (see `StarterApp`).
public struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings
    private let model: StarterModel

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(InvisibleWindow())
            .onChange(of: model.settingsRequest) {
                NSApp.activate()
                openSettings()
            }
    }
}

/// Makes its window invisible, click-through, and out of ⌘` and the Window menu.
struct InvisibleWindow: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask = [.borderless]
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isExcludedFromWindowsMenu = true
            window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
            window.setFrame(NSRect(x: 0, y: 0, width: 1, height: 1), display: false)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
