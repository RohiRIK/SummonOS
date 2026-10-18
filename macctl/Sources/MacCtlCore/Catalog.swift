import Foundation

/// Every setting macctl knows. Ids are `<domain>.<name>`, lowercase kebab.
/// `verifiedOn` stays empty until a human checks the setting on a real Mac.
public enum Catalog {
    public static let all: [Setting] = dock + finder + keyboard + screenshots + appearance + desktop

    // MARK: Dock

    private static let restartDock: [SideEffect] = [.restart(process: "Dock")]

    static let dock: [Setting] = [
        Setting(
            id: "dock.autohide",
            summary: "Hide the Dock until the pointer reaches the screen edge (true = hidden).",
            type: .bool,
            backend: .defaults(domain: "com.apple.dock", key: "autohide", type: .bool),
            after: restartDock,
            systemDefault: .bool(false)
        ),
        Setting(
            id: "dock.tilesize",
            summary: "Dock icon size in points, 16 (tiny) to 128 (huge).",
            type: .int(min: 16, max: 128),
            backend: .defaults(domain: "com.apple.dock", key: "tilesize", type: .int),
            after: restartDock,
            systemDefault: .int(48)
        ),
        Setting(
            id: "dock.show-recents",
            summary: "Show recently used apps in their own Dock section (false = hide them).",
            type: .bool,
            backend: .defaults(domain: "com.apple.dock", key: "show-recents", type: .bool),
            after: restartDock,
            systemDefault: .bool(true)
        ),
        Setting(
            id: "dock.orientation",
            summary: "Screen edge the Dock sits on: left, bottom, or right.",
            type: .enumeration(["left", "bottom", "right"]),
            backend: .defaults(domain: "com.apple.dock", key: "orientation", type: .string),
            after: restartDock,
            systemDefault: .string("bottom")
        ),
        Setting(
            id: "dock.minimize-effect",
            summary: "Animation when minimizing a window into the Dock: genie, scale, or suck (suck is hidden in System Settings).",
            type: .enumeration(["genie", "scale", "suck"]),
            backend: .defaults(domain: "com.apple.dock", key: "mineffect", type: .string),
            after: restartDock,
            systemDefault: .string("genie")
        ),
        Setting(
            id: "dock.autohide-delay",
            summary: "Seconds the pointer must rest at the edge before a hidden Dock appears, 0 to 5 (0 = instant); only matters with dock.autohide.",
            type: .double(min: 0, max: 5),
            backend: .defaults(domain: "com.apple.dock", key: "autohide-delay", type: .float),
            after: restartDock,
            systemDefault: .double(0.5)
        ),
    ]

    // MARK: Finder

    private static let restartFinder: [SideEffect] = [.restart(process: "Finder")]

    static let finder: [Setting] = [
        Setting(
            id: "finder.show-extensions",
            summary: "Show every file name extension (.txt, .app) in Finder and open/save dialogs (true = show).",
            type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "AppleShowAllExtensions", type: .bool),
            after: restartFinder,
            systemDefault: .bool(false)
        ),
        Setting(
            id: "finder.show-pathbar",
            summary: "Show the path bar (folder breadcrumbs) at the bottom of Finder windows.",
            type: .bool,
            backend: .defaults(domain: "com.apple.finder", key: "ShowPathbar", type: .bool),
            after: restartFinder,
            systemDefault: .bool(false)
        ),
        Setting(
            id: "finder.show-statusbar",
            summary: "Show the status bar (item count, free space) at the bottom of Finder windows.",
            type: .bool,
            backend: .defaults(domain: "com.apple.finder", key: "ShowStatusBar", type: .bool),
            after: restartFinder,
            systemDefault: .bool(false)
        ),
        Setting(
            id: "finder.default-view",
            summary: "View for new Finder windows, raw codes: Nlsv = list, icnv = icons, clmv = columns, glyv = gallery; folders with saved views keep theirs.",
            type: .enumeration(["Nlsv", "icnv", "clmv", "glyv"]),
            backend: .defaults(domain: "com.apple.finder", key: "FXPreferredViewStyle", type: .string),
            after: restartFinder,
            systemDefault: .string("icnv")
        ),
        Setting(
            id: "finder.show-hidden",
            summary: "Show hidden files (dotfiles, ~/Library) in Finder; same as toggling Cmd-Shift-. (true = show).",
            type: .bool,
            backend: .defaults(domain: "com.apple.finder", key: "AppleShowAllFiles", type: .bool),
            after: restartFinder,
            systemDefault: .bool(false)
        ),
    ]

    // MARK: Keyboard

    static let keyboard: [Setting] = [
        Setting(
            id: "keyboard.key-repeat",
            summary: "Key repeat interval in 15 ms units, 1 to 120; lower is faster (2 = 30 ms, fastest in System Settings). Takes effect after logout.",
            type: .int(min: 1, max: 120),
            backend: .defaults(domain: Backend.globalDomain, key: "KeyRepeat", type: .int),
            after: [.logout],
            systemDefault: .int(6)
        ),
        Setting(
            id: "keyboard.initial-key-repeat",
            summary: "Delay before a held key starts repeating, in 15 ms units, 10 to 120; lower is sooner (15 = 225 ms, shortest in System Settings). Takes effect after logout.",
            type: .int(min: 10, max: 120),
            backend: .defaults(domain: Backend.globalDomain, key: "InitialKeyRepeat", type: .int),
            after: [.logout],
            systemDefault: .int(25)
        ),
        Setting(
            id: "keyboard.press-and-hold",
            summary: "Holding a key shows the accent picker (true) instead of repeating the key (false). Takes effect after logout.",
            type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "ApplePressAndHoldEnabled", type: .bool),
            after: [.logout],
            systemDefault: .bool(true)
        ),
    ]

    // MARK: Screenshots

    private static let restartUIServer: [SideEffect] = [.restart(process: "SystemUIServer")]

    static let screenshots: [Setting] = [
        Setting(
            id: "screenshots.location",
            summary: "Folder where new screenshots are saved; ~ is expanded and a missing folder is created.",
            type: .path,
            backend: .defaults(domain: "com.apple.screencapture", key: "location", type: .string),
            after: restartUIServer,
            systemDefault: .string("~/Desktop")
        ),
        Setting(
            id: "screenshots.format",
            summary: "File format for new screenshots: png, jpg, pdf, heic, or tiff.",
            type: .enumeration(["png", "jpg", "pdf", "heic", "tiff"]),
            backend: .defaults(domain: "com.apple.screencapture", key: "type", type: .string),
            after: restartUIServer,
            systemDefault: .string("png")
        ),
        Setting(
            id: "screenshots.disable-shadow",
            summary: "Omit the drop shadow when capturing a single window (true = no shadow).",
            type: .bool,
            backend: .defaults(domain: "com.apple.screencapture", key: "disable-shadow", type: .bool),
            after: restartUIServer,
            systemDefault: .bool(false)
        ),
    ]

    // MARK: Appearance

    static let appearance: [Setting] = [
        Setting(
            id: "appearance.dark-mode",
            summary: "System-wide Dark Mode (true = dark, false = light); applies instantly, needs Automation access to System Events.",
            type: .bool,
            permissions: [.automation(bundleID: "com.apple.systemevents")],
            backend: .appleScript(
                get: """
                tell application "System Events" to tell appearance preferences to get dark mode
                """,
                set: """
                on run argv
                    tell application "System Events" to tell appearance preferences to set dark mode to ((item 1 of argv) is "true")
                end run
                """
            ),
            systemDefault: .bool(false)
        ),
    ]

    // MARK: Desktop

    static let desktop: [Setting] = [
        Setting(
            id: "desktop.wallpaper",
            summary: "Desktop picture for every screen: an absolute path (or ~) to an existing image file; reads the main screen's picture.",
            type: .path,
            backend: .wallpaper
        ),
    ]
}
