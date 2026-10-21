import Foundation
#if canImport(AppKit)
import AppKit
import CoreGraphics
#endif

/// Display UUIDs survive screen ordering changes and reconnects; paths remain ordinary scalar values.
public struct DisplayWallpaper: Sendable, Hashable, Codable {
    public let displayID: String
    public let path: String
    public init(displayID: String, path: String) {
        self.displayID = displayID
        self.path = path
    }
}

/// Reads and sets the desktop picture. Injected into `SystemBackend` so tests use a fake.
public protocol WallpaperControlling: Sendable {
    /// Path of the main screen's desktop picture, or nil when there is no screen.
    func currentWallpaper() async throws -> String?
    /// Sets `path` as the desktop picture of every screen.
    func setWallpaper(_ path: String) async throws
    func wallpapers() async throws -> [DisplayWallpaper]?
    func restoreWallpapers(_ wallpapers: [DisplayWallpaper]) async throws
}

extension WallpaperControlling {
    /// Existing injected controllers and legacy snapshots keep their scalar behavior.
    public func wallpapers() async throws -> [DisplayWallpaper]? { nil }
    public func restoreWallpapers(_ wallpapers: [DisplayWallpaper]) async throws {
        throw MacCtlError.unsupported(id: "desktop.wallpaper", reason: "per-display restoration is unavailable")
    }
}

#if canImport(AppKit)
/// The real desktop picture, through `NSWorkspace`. AppKit screen APIs run on the main actor.
public struct LiveWallpaper: WallpaperControlling {
    public init() {}

    private static func displayID(_ screen: NSScreen) throws -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            throw MacCtlError.unsupported(id: "desktop.wallpaper", reason: "cannot identify a connected display")
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    public func wallpapers() async throws -> [DisplayWallpaper]? {
        try await MainActor.run {
            try NSScreen.screens.map { screen in
                guard let path = NSWorkspace.shared.desktopImageURL(for: screen)?.path(percentEncoded: false) else {
                    throw MacCtlError.unsupported(id: "desktop.wallpaper", reason: "cannot capture a display's wallpaper")
                }
                return DisplayWallpaper(displayID: try Self.displayID(screen), path: path)
            }.sorted { $0.displayID < $1.displayID }
        }
    }

    public func restoreWallpapers(_ wallpapers: [DisplayWallpaper]) async throws {
        try await MainActor.run {
            let screens = try NSScreen.screens.map { (try Self.displayID($0), $0) }
            // Fail before changing any display when its saved target cannot be restored. Reconnecting
            // the display makes this same backup retryable, rather than silently consuming its state.
            guard wallpapers.allSatisfy({ saved in screens.contains { $0.0 == saved.displayID } }) else {
                throw MacCtlError.unsupported(id: "desktop.wallpaper", reason: "reconnect the displays recorded in the snapshot before restoring")
            }
            for saved in wallpapers {
                guard let screen = screens.first(where: { $0.0 == saved.displayID })?.1 else { continue }
                let workspace = NSWorkspace.shared
                try workspace.setDesktopImageURL(URL(fileURLWithPath: saved.path), for: screen,
                                                options: workspace.desktopImageOptions(for: screen) ?? [:])
            }
        }
    }

    public func currentWallpaper() async throws -> String? {
        await MainActor.run {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
            return NSWorkspace.shared.desktopImageURL(for: screen)?.path(percentEncoded: false)
        }
    }

    public func setWallpaper(_ path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try await MainActor.run {
            let screens = NSScreen.screens
            guard !screens.isEmpty else {
                throw MacCtlError.commandFailed(
                    command: "NSWorkspace setDesktopImageURL", exitCode: 1, stderr: "no screens found")
            }
            let workspace = NSWorkspace.shared
            for screen in screens {
                // Keep each screen's scaling and fill color; only the picture changes.
                let options = workspace.desktopImageOptions(for: screen) ?? [:]
                do {
                    try workspace.setDesktopImageURL(url, for: screen, options: options)
                } catch {
                    throw MacCtlError.commandFailed(
                        command: "NSWorkspace setDesktopImageURL", exitCode: 1,
                        stderr: error.localizedDescription)
                }
            }
        }
    }
}
#else
/// Non-macOS builds (Linux CI for the journal and recovery logic) have no desktop picture.
public struct LiveWallpaper: WallpaperControlling {
    public init() {}
    public func currentWallpaper() async throws -> String? {
        throw MacCtlError.unsupported(id: "desktop.wallpaper", reason: "requires macOS")
    }
    public func setWallpaper(_ path: String) async throws {
        throw MacCtlError.unsupported(id: "desktop.wallpaper", reason: "requires macOS")
    }
}
#endif
