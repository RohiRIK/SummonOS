import AppKit
import ScreenSaver
import StarterCore

/// The screensaver. `NSPrincipalClass` in Resources/Info.plist names this class, so the Objective-C name is fixed.
@objc(StarterView)
public final class StarterView: ScreenSaverView {
    private var drift = Drift(count: 0, width: 1, height: 1)
    // Set once in setUp and read in deinit, which is not on the main actor.
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        animationTimeInterval = 1.0 / 30
        // The preview pane is tiny: fewer dots there.
        drift = Drift(count: isPreview ? 12 : 48, width: bounds.width, height: bounds.height)
        // legacyScreenSaver keeps running after the saver closes; stop drawing when macOS says it stopped.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAnimation() }
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        drift.resize(width: bounds.width, height: bounds.height)
    }

    public override func animateOneFrame() {
        drift.step(seconds: animationTimeInterval)
        needsDisplay = true
    }

    public override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        NSColor.systemPurple.setFill()
        let size: Double = isPreview ? 3 : 6
        for dot in drift.dots {
            NSBezierPath(ovalIn: NSRect(x: dot.x - size / 2, y: dot.y - size / 2, width: size, height: size)).fill()
        }
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
