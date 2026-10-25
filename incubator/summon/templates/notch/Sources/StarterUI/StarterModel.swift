import AppKit
import Observation
import StarterCore

/// UI state for the notch panel. Views read it; Core keeps the shelf.
@MainActor
@Observable
public final class StarterModel {
    public private(set) var shelf: Shelf {
        didSet { UserDefaults.standard.set(shelf.stored, forKey: StarterSettings.shelfKey) }
    }
    /// Open while the pointer or a dragged file is over the panel, and a moment after it leaves.
    public private(set) var isOpen = false
    private var isHovering = false
    private var isDropTargeted = false
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    /// The camera housing's height: open content starts below it. 0 on a screen without one.
    public var topInset: CGFloat = 0
    /// Bumped by Settings…; `SettingsOpener` opens the Settings window.
    public private(set) var settingsRequest = 0

    public init(shelf: Shelf? = nil) {
        var saved = shelf ?? Shelf(stored: UserDefaults.standard.stringArray(forKey: StarterSettings.shelfKey) ?? [])
        saved.prune()
        self.shelf = saved
    }

    public func setHovering(_ inside: Bool) {
        isHovering = inside
        update()
    }

    public func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
        update()
    }

    /// From the menu bar menu: open for a few seconds, longer if the pointer moves onto it.
    public func show() {
        isOpen = true
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, !self.isHovering, !self.isDropTargeted else { return }
            self.isOpen = false
        }
    }

    private func update() {
        closeTask?.cancel()
        if isHovering || isDropTargeted {
            isOpen = true
            return
        }
        // A short grace period, so brushing past the edge doesn't snap it shut.
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.isOpen = false
        }
    }

    public func add(_ urls: [URL]) {
        shelf.add(urls.filter(\.isFileURL))
    }

    public func remove(_ url: URL) {
        shelf.remove(url)
    }

    public func clear() {
        shelf.clear()
    }

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func requestSettings() {
        settingsRequest += 1
    }
}

/// UserDefaults keys shared by the Settings window and the app delegate.
public enum StarterSettings {
    public static let showInMenuBarKey = "showInMenuBar"
    public static let showWithoutNotchKey = "showWithoutNotch"
    public static let shelfKey = "shelf"
}

extension StarterModel {
    /// An open shelf with a few files for previews and `--screenshot`.
    static var preview: StarterModel {
        let files = ["/Applications/Safari.app", "/System/Library/CoreServices/Finder.app", "/etc/hosts"]
        let model = StarterModel(shelf: Shelf(files: files.map { URL(fileURLWithPath: $0) }))
        model.isOpen = true
        return model
    }
}
