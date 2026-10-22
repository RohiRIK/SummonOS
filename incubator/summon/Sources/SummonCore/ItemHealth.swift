import Foundation

/// Health status for an individual app or theme.
public struct ItemHealth: Sendable, Equatable {
    public enum Level: String, Sendable, Codable, Comparable {
        case healthy
        case warning
        case error

        var rank: Int {
            switch self {
            case .healthy: return 0
            case .warning: return 1
            case .error: return 2
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }
    }

    public var level: Level
    public var badge: String
    public var detail: String
    public var fixPrompt: String?

    public init(level: Level, badge: String, detail: String, fixPrompt: String? = nil) {
        self.level = level
        self.badge = badge
        self.detail = detail
        self.fixPrompt = fixPrompt
    }

    public var isHealthy: Bool { level == .healthy }

    public static let healthy = ItemHealth(
        level: .healthy,
        badge: "Healthy",
        detail: "All files and configuration are healthy."
    )
}

public enum AppHealthChecker {
    /// Checks health of a project in ~/Summon/Apps/<name>.
    public static func check(
        project: Project,
        recentCrashes: [CrashReport] = [],
        fileManager: FileManager = .default
    ) -> ItemHealth {
        let folder = URL(fileURLWithPath: project.path)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            return ItemHealth(
                level: .error,
                badge: "Folder Missing",
                detail: "Project folder does not exist at \(project.path).",
                fixPrompt: "Project '\(project.name)' is registered in Summon but its folder \(project.path) is missing. Restore or recreate it."
            )
        }

        let pkg = folder.appendingPathComponent("Package.swift")
        guard fileManager.fileExists(atPath: pkg.path) else {
            return ItemHealth(
                level: .error,
                badge: "Missing Package.swift",
                detail: "Package.swift is missing from \(project.name).",
                fixPrompt: "Project '\(project.name)' at \(project.path) is missing Package.swift. Restore the Swift package configuration."
            )
        }

        // Check for recent crashes
        if let crash = recentCrashes.first(where: { $0.program.lowercased() == project.name.lowercased() }) {
            return ItemHealth(
                level: .error,
                badge: "Crashed",
                detail: "Crashed recently (\(crash.signal ?? crash.exceptionType ?? "crash")).",
                fixPrompt: "App '\(project.name)' at \(project.path) crashed recently (report: \(crash.file)). Diagnose the crash using diagnose-crash-mac skill and fix it."
            )
        }

        // Check build status
        let buildFolder = folder.appendingPathComponent("build")
        let dotBuild = folder.appendingPathComponent(".build")
        let appBundle = buildFolder.appendingPathComponent("\(project.name).app")
        let hasBuild = fileManager.fileExists(atPath: appBundle.path) || fileManager.fileExists(atPath: dotBuild.path)
        if !hasBuild {
            return ItemHealth(
                level: .warning,
                badge: "Needs Build",
                detail: "App has not been built yet.",
                fixPrompt: "Build project '\(project.name)' at \(project.path) using scripts/bundle.sh or swift build and make sure it builds cleanly."
            )
        }

        return ItemHealth(
            level: .healthy,
            badge: "Healthy",
            detail: "Project folder, Package.swift, and build artifacts present."
        )
    }

    /// Checks health of a theme palette in ~/.config/summon/themes/<slug>.
    public static func check(
        theme: Theme,
        themesFolder: URL,
        fileManager: FileManager = .default
    ) -> ItemHealth {
        let folder = themesFolder.appendingPathComponent(theme.slug)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            return ItemHealth(
                level: .error,
                badge: "Folder Missing",
                detail: "Theme directory missing at \(folder.path).",
                fixPrompt: "Theme '\(theme.name)' (slug: \(theme.slug)) directory is missing from ~/.config/summon/themes. Recreate it with theme.json."
            )
        }

        let jsonFile = folder.appendingPathComponent("theme.json")
        guard fileManager.fileExists(atPath: jsonFile.path) else {
            return ItemHealth(
                level: .error,
                badge: "Missing theme.json",
                detail: "theme.json is missing in \(theme.slug).",
                fixPrompt: "Theme '\(theme.name)' at \(folder.path) is missing theme.json. Restore or generate it."
            )
        }

        // Check wallpaper images
        if theme.wallpapers.isEmpty {
            return ItemHealth(
                level: .warning,
                badge: "No Wallpaper",
                detail: "Theme has no wallpaper images configured or generated.",
                fixPrompt: "Theme '\(theme.name)' (slug: \(theme.slug)) in \(folder.path) has no wallpaper images. Generate a wallpaper image matching the theme using summon-art skill, save it to \(folder.path), and update theme.json."
            )
        }

        for wp in theme.wallpapers {
            let wpPath = folder.appendingPathComponent(wp).path
            if !fileManager.fileExists(atPath: wpPath) {
                return ItemHealth(
                    level: .error,
                    badge: "Missing Image",
                    detail: "Wallpaper image '\(wp)' is missing from \(theme.slug).",
                    fixPrompt: "Theme '\(theme.name)' in \(folder.path) references wallpaper '\(wp)' but the file is missing. Generate or restore this image using summon-art skill."
                )
            }
        }

        // Check color contrast problems
        let problems = ThemeLint.problems(theme)
        if let err = problems.first(where: { $0.severity == .error }) {
            return ItemHealth(
                level: .error,
                badge: "Contrast Error",
                detail: err.message,
                fixPrompt: "Theme '\(theme.name)' in \(folder.path) has a contrast error: \(err.message). Adjust the colors in theme.json so text is readable."
            )
        }
        if let warn = problems.first(where: { $0.severity == .warning }) {
            return ItemHealth(
                level: .warning,
                badge: "Low Contrast",
                detail: warn.message,
                fixPrompt: "Theme '\(theme.name)' in \(folder.path) has a contrast warning: \(warn.message). Adjust the colors in theme.json."
            )
        }

        return ItemHealth(
            level: .healthy,
            badge: "Healthy",
            detail: "Theme JSON, wallpaper assets, and contrast checks pass."
        )
    }
}
