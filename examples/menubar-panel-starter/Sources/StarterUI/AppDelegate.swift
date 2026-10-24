import AppKit
import Observation
import SwiftUI

/// Owns what outlives a view: the status item, its panel and the live label.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let model = StarterModel()
    public private(set) var panel: PanelController?
    private var defaultsObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let model = self.model
        let panel = PanelController(image: NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "Starter"),
                                    openSettings: { model.requestSettings() }) { actions in
            PanelView(model: model, actions: actions)
        }
        self.panel = panel
        trackLabel()
        // The Settings window writes the menu bar setting through @AppStorage.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLabel() }
        }
    }

    /// Redraws the label whenever the model changes, panel open or not.
    private func trackLabel() {
        withObservationTracking {
            updateLabel()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackLabel() }
        }
    }

    private func updateLabel() {
        let showCount = UserDefaults.standard.bool(forKey: StarterSettings.showCountKey)
        panel?.setLabel(title: showCount ? "\(model.counter.value)" : nil,
                        accessibilityLabel: "Starter, \(model.counter.label)")
    }
}
