import AppKit
import Foundation

/// Reads and sets the desktop picture. Injected into `SystemBackend` so tests use a fake.
public protocol WallpaperControlling: Sendable {
    /// Path of the main screen's desktop picture, or nil when there is no screen.
    func currentWallpaper() async throws -> String?
    /// Sets `path` as the desktop picture of every screen.
    func setWallpaper(_ path: String) async throws
}

/// The real desktop picture, through `NSWorkspace`. AppKit screen APIs run on the main actor.
public struct LiveWallpaper: WallpaperControlling {
    public init() {}

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
