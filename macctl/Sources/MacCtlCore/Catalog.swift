import Foundation

/// Every setting macctl knows. Ids are `<domain>.<name>`, lowercase kebab.
/// `verifiedOn` stays empty until a human checks the setting on a real Mac.
public enum Catalog {
    public static let all: [Setting] = dock + finder + keyboard + screenshots + appearance + desktop
        + windows + menubar + documents

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
        Setting(
            id: "dock.magnification",
            summary: "Enlarge Dock icons under the pointer (true = magnify); the size is dock.magnified-size.",
            type: .bool,
            backend: .defaults(domain: "com.apple.dock", key: "magnification", type: .bool),
            after: restartDock,
            systemDefault: .bool(false)
        ),
        Setting(
            id: "dock.magnified-size",
            summary: "Icon size in points under the pointer when dock.magnification is on, 16 to 512.",
            type: .int(min: 16, max: 512),
            backend: .defaults(domain: "com.apple.dock", key: "largesize", type: .int),
            after: restartDock
        ),
        Setting(
            id: "dock.show-indicators",
            summary: "Show a dot under apps that are open (false = no dots).",
            type: .bool,
            backend: .defaults(domain: "com.apple.dock", key: "show-process-indicators", type: .bool),
            after: restartDock,
            systemDefault: .bool(true)
        ),
        Setting(
            id: "dock.only-open-apps",
            summary: "Show only apps that are open in the Dock, hiding pinned apps that are not running (true = only open).",
            type: .bool,
            backend: .defaults(domain: "com.apple.dock", key: "static-only", type: .bool),
            after: restartDock,
            systemDefault: .bool(false)
        ),
        Setting(
            id: "dock.autohide-speed",
            summary: "Seconds the hidden Dock takes to slide in or out, 0 to 5 (0 = no animation); only matters with dock.autohide.",
            type: .double(min: 0, max: 5),
            backend: .defaults(domain: "com.apple.dock", key: "autohide-time-modifier", type: .float),
            after: restartDock
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
        Setting(
            id: "finder.folders-first",
            summary: "Keep folders above files when Finder windows are sorted by name (true = folders first).",
            type: .bool,
            backend: .defaults(domain: "com.apple.finder", key: "_FXSortFoldersFirst", type: .bool),
            after: restartFinder,
            systemDefault: .bool(false)
        ),
        Setting(
            id: "finder.warn-extension-change",
            summary: "Ask before changing a file name extension in Finder (false = rename without asking).",
            type: .bool,
            backend: .defaults(domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning", type: .bool),
            after: restartFinder,
            systemDefault: .bool(true)
        ),
        Setting(
            id: "finder.search-scope",
            summary: "Where a Finder window search looks, raw codes: SCev = this Mac, SCcf = the current folder, SCsp = the previous scope.",
            type: .enumeration(["SCev", "SCcf", "SCsp"]),
            backend: .defaults(domain: "com.apple.finder", key: "FXDefaultSearchScope", type: .string),
            after: restartFinder,
            systemDefault: .string("SCev")
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
        Setting(
            id: "screenshots.show-thumbnail",
            summary: "Show the floating thumbnail after a capture (false = save at once, with no thumbnail delay).",
            type: .bool,
            backend: .defaults(domain: "com.apple.screencapture", key: "show-thumbnail", type: .bool),
            after: restartUIServer,
            systemDefault: .bool(true)
        ),
        Setting(
            id: "screenshots.include-date",
            summary: "Put the date and time in screenshot file names (false = \"Screenshot\" plus a number).",
            type: .bool,
            backend: .defaults(domain: "com.apple.screencapture", key: "include-date", type: .bool),
            after: restartUIServer,
            systemDefault: .bool(true)
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
        Setting(
            id: "appearance.scroll-bars",
            summary: "When scroll bars show: Automatic (by input device), WhenScrolling, or Always. Apps pick it up when reopened.",
            type: .enumeration(["Automatic", "WhenScrolling", "Always"]),
            backend: .defaults(domain: Backend.globalDomain, key: "AppleShowScrollBars", type: .string),
            after: [.relaunchApps],
            systemDefault: .string("Automatic")
        ),
        Setting(
            id: "appearance.menu-icons",
            summary: "Show the small icons next to menu items that macOS 26 added (false = text-only menus). Apps pick it up when reopened.",
            type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "NSMenuEnableActionImages", type: .bool),
            after: [.relaunchApps],
            systemDefault: .bool(true),
            minimumOS: "26.0"
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

    // MARK: Windows (com.apple.WindowManager)

    static let windows: [Setting] = [
        Setting(
            id: "windows.click-desktop-to-reveal",
            summary: "Clicking the wallpaper moves every window aside to show the desktop (false = only in Stage Manager).",
            type: .bool,
            backend: .defaults(domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop", type: .bool),
            systemDefault: .bool(true)
        ),
        Setting(
            id: "windows.tile-by-edge-drag",
            summary: "Dragging a window to a screen edge tiles it (false = edges do nothing).",
            type: .bool,
            backend: .defaults(domain: "com.apple.WindowManager", key: "EnableTilingByEdgeDrag", type: .bool),
            systemDefault: .bool(true)
        ),
        Setting(
            id: "windows.tile-margins",
            summary: "Leave gaps between tiled windows (false = tiled windows touch edge to edge).",
            type: .bool,
            backend: .defaults(domain: "com.apple.WindowManager", key: "EnableTiledWindowMargins", type: .bool),
            systemDefault: .bool(true)
        ),
    ]

    // MARK: Menu bar

    static let menubar: [Setting] = [
        Setting(
            id: "menubar.agent",
            summary: "macOS 27's hidden menu bar agent, which menubar.keyboard-navigation needs (true = on). Takes effect after logout.",
            type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "NSMenuEnableMenuBarAgent", type: .bool),
            after: [.logout],
            systemDefault: .bool(false),
            minimumOS: "27.0"
        ),
        Setting(
            id: "menubar.keyboard-navigation",
            summary: "Arrow keys move from the app's last menu into the status menus and back (macOS 27, hidden; needs menubar.agent). Takes effect after logout.",
            type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "NSMenuBarUseAgentNavigation", type: .bool),
            after: [.logout],
            systemDefault: .bool(false),
            minimumOS: "27.0"
        ),
    ]

    // MARK: Documents and text

    static let documents: [Setting] = [
        Setting(
            id: "documents.save-to-icloud",
            summary: "New documents save to iCloud Drive by default (false = save to this Mac). Apps pick it up when reopened.",
            type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "NSDocumentSaveNewDocumentsToCloud", type: .bool),
            after: [.relaunchApps],
            systemDefault: .bool(true)
        ),
        Setting(
            id: "documents.autocorrect",
            summary: "Correct spelling automatically while typing (false = only underline mistakes). Apps pick it up when reopened.",
            type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "NSAutomaticSpellingCorrectionEnabled", type: .bool),
            after: [.relaunchApps],
            systemDefault: .bool(true)
        ),
    ]
}
