import CoreGraphics
import Foundation
import Observation
import StarterCore

/// UI state for the HUD. Views read it; Core keeps the time.
@MainActor
@Observable
public final class StarterModel {
    public private(set) var stopwatch = Stopwatch()
    public var isHUDVisible = false
    /// The corner the HUD rests in; saved, so it comes back there next launch.
    public var corner: Corner {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: StarterSettings.cornerKey) }
    }
    /// Bumped by Settings…; `SettingsOpener` opens the Settings window.
    public private(set) var settingsRequest = 0

    @ObservationIgnored var dragEnded: @MainActor (CGVector) -> Void = { _ in }

    public init() {
        corner = UserDefaults.standard.string(forKey: StarterSettings.cornerKey).flatMap(Corner.init(rawValue:)) ?? .topRight
    }

    public func toggle() {
        stopwatch.toggle(at: Date())
    }

    public func reset() {
        stopwatch.reset()
    }

    public func requestSettings() {
        settingsRequest += 1
    }
}

/// UserDefaults keys shared by the Settings window, the right-click menu and the app delegate.
public enum StarterSettings {
    public static let hotKeyKey = "startPauseHotKey"
    public static let showInMenuBarKey = "showInMenuBar"
    public static let opacityKey = "hudOpacity"
    public static let sizeKey = "hudSize"
    public static let cornerKey = "hudCorner"
}

extension StarterModel {
    /// A running stopwatch for previews and `--screenshot`.
    static var preview: StarterModel {
        let model = StarterModel()
        model.stopwatch.start(at: Date().addingTimeInterval(-754))
        return model
    }
}
