import AppKit
import Observation
import StarterCore

/// UI state for the launcher. Views read it; Core finds and ranks.
@MainActor
@Observable
public final class StarterModel {
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            results = FuzzyMatch.rank(catalog, query: query)
            selection = 0
            showingActions = false
            status = nil
        }
    }
    public private(set) var results: [Launchable] = []
    public var selection = 0
    public var showingActions = false
    /// A one-line message in the footer ("Couldn't open…"); cleared by the next keystroke.
    public private(set) var status: String?
    /// A file dropped on the launcher: the next app run opens it.
    public var droppedFile: URL?
    /// Bumped by Settings…; `SettingsOpener` opens the Settings window.
    public private(set) var settingsRequest = 0

    @ObservationIgnored var close: @MainActor () -> Void = {}
    private var catalog: [Launchable]
    @ObservationIgnored private var scannedAt: Date?
    @ObservationIgnored private var scannedStamp: [Date?] = []

    public init(catalog: [Launchable] = []) {
        self.catalog = catalog
    }

    public var selected: Launchable? { results.indices.contains(selection) ? results[selection] : nil }

    /// Fresh state for each open. The app list is rescanned in the background only when an app folder changed or
    /// the last scan is a few minutes old, so opening the launcher again costs almost nothing.
    func prepareForOpen() {
        query = ""
        droppedFile = nil
        showingActions = false
        let stamp = AppCatalog.stamp()
        if let scannedAt, Date().timeIntervalSince(scannedAt) < 300, stamp == scannedStamp { return }
        scannedAt = Date()
        scannedStamp = stamp
        Task {
            let apps = await Task.detached(priority: .utility) { AppCatalog.scan() }.value
            catalog = apps
            if !query.isEmpty { results = FuzzyMatch.rank(apps, query: query) }
        }
    }

    public func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    /// ⌘1…⌘9 and a click run the item at that position.
    public func run(at index: Int) {
        guard results.indices.contains(index) else { return }
        selection = index
        open(results[index])
    }

    public func runSelected() {
        if let selected { open(selected) }
    }

    public func open(_ item: Launchable) {
        let app = URL(fileURLWithPath: item.path)
        let configuration = NSWorkspace.OpenConfiguration()
        if let file = droppedFile {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: configuration) { _, error in
                if let error { Task { @MainActor in self.fail(error, item) } }
            }
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                if let error { Task { @MainActor in self.fail(error, item) } }
            }
        }
        close()
    }

    public func reveal(_ item: Launchable) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        close()
    }

    public func copyPath(_ item: Launchable) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
        status = "Copied the path of \(item.title)"
        showingActions = false
    }

    public func requestSettings() {
        close()
        settingsRequest += 1
    }

    public func clearStatus() {
        status = nil
    }

    private func fail(_ error: Error, _ item: Launchable) {
        // The panel has closed by now: the message waits in the footer for the next open.
        status = "Couldn't open \(item.title): \(error.localizedDescription)"
        NSSound.beep()
    }
}

/// UserDefaults keys shared by the Settings window and the app delegate.
public enum StarterSettings {
    public static let hotKeyKey = "launcherHotKey"
    public static let showInMenuBarKey = "showInMenuBar"
}

extension StarterModel {
    /// Sample state for previews and `--screenshot`.
    static var preview: StarterModel {
        let apps = ["Safari", "Shortcuts", "Screenshot", "System Settings", "Stickies"]
            .map { Launchable(title: $0, path: "/System/Applications/\($0).app") }
        let model = StarterModel(catalog: apps)
        model.query = "s"
        return model
    }
}
