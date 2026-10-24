import Foundation

/// Health status for an individual app, theme, or art job.
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
        detail: "All code, assets, and art checks pass."
    )
}

/// An art generation job in ~/Summon/Art/<job>.
public struct ArtJob: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var path: String
    public var images: [String]
    public var kind: Kind

    public enum Kind: String, Sendable, Codable {
        case wallpaper
        case icon
        case general

        public var title: String {
            switch self {
            case .wallpaper: return "Wallpaper Art"
            case .icon: return "App Icon Art"
            case .general: return "Art Job"
            }
        }

        public var systemImage: String {
            switch self {
            case .wallpaper: return "photo.artframe"
            case .icon: return "app.dashed"
            case .general: return "paintpalette"
            }
        }
    }

    public init(name: String, path: String, images: [String], kind: Kind) {
        self.name = name
        self.path = path
        self.images = images
        self.kind = kind
    }
}

public enum AppHealthChecker {
    /// Comprehensive health and art inspection of a project in ~/Summon/Apps/<name>.
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
                fixPrompt: "Summon's project '\(project.name)' points at \(project.path), which no longer exists. Look for where it went (Trash, a rename, `summon project list`, its GitHub repo). Tell me what you found and ask before restoring it, cloning it again, or removing the entry with `summon project forget \(project.name)`."
            )
        }

        let pkg = folder.appendingPathComponent("Package.swift")
        guard fileManager.fileExists(atPath: pkg.path) else {
            return ItemHealth(
                level: .error,
                badge: "Missing Package.swift",
                detail: "Package.swift is missing from \(project.name).",
                fixPrompt: "Project '\(project.name)' at \(project.path) has no Package.swift, so it cannot build. Check git first (`git status`, `git log -- Package.swift`) and restore it from history if it was deleted; only write a new one if it never existed, matching the layout in the mac-app skill. Finish when `scripts/check.sh` passes."
            )
        }

        // Check for recent crashes
        if let crash = recentCrashes.first(where: { $0.program.lowercased() == project.name.lowercased() }) {
            return ItemHealth(
                level: .error,
                badge: "Crashed",
                detail: "Crashed recently (\(crash.signal ?? crash.exceptionType ?? "crash")).",
                fixPrompt: "My app '\(project.name)' (\(project.path), built with Summon) crashed (report: \(crash.file)). Find the cause with the diagnose-crash-mac skill. This is our own code, so fix it: change the code, add a Core test that reproduces it when the cause is logic, run `scripts/check.sh`, relaunch the app, and tell me what was wrong."
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
                fixPrompt: "Project '\(project.name)' at \(project.path) has not been built yet. Run `scripts/check.sh` there (then `scripts/bundle.sh` if it has one), fix whatever fails, and tell me what you changed."
            )
        }

        // --- ART INSPECTION RULES ---

        // 1. App Icon Art inspection
        let resourcesFolder = folder.appendingPathComponent("Resources")
        let hasAppIcon = fileManager.fileExists(atPath: resourcesFolder.appendingPathComponent("AppIcon.icns").path)
            || fileManager.fileExists(atPath: folder.appendingPathComponent("AppIcon.icns").path)

        // 2. UI Screenshots / Showcase Art inspection
        let shotsFolder = folder.appendingPathComponent("docs/screenshots")
        let shots = (try? fileManager.contentsOfDirectory(atPath: shotsFolder.path))?
            .filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") } ?? []
        let hasScreenshots = !shots.isEmpty

        if !hasAppIcon && !hasScreenshots {
            return ItemHealth(
                level: .warning,
                badge: "Missing Art",
                detail: "Missing both custom AppIcon.icns and UI screenshots.",
                fixPrompt: "Project '\(project.name)' at \(project.path) is missing custom AppIcon art and UI screenshots. Use summon-art skill (icons.md) to generate an icon in Resources/AppIcon.icns, and run 'summon project shots \(project.name)' to capture UI screenshots for Showcase."
            )
        }

        if !hasAppIcon {
            return ItemHealth(
                level: .warning,
                badge: "No AppIcon",
                detail: "Missing custom AppIcon.icns in Resources/.",
                fixPrompt: "Project '\(project.name)' at \(project.path) is missing an AppIcon. Use summon-art skill (icons.md) to generate custom icon art and save as Resources/AppIcon.icns."
            )
        }

        if !hasScreenshots {
            return ItemHealth(
                level: .warning,
                badge: "No Screenshots",
                detail: "Missing UI screenshots in docs/screenshots/.",
                fixPrompt: "Project '\(project.name)' at \(project.path) has no UI screenshots. Run 'summon project shots \(project.name)' to capture panel screenshots and update the README and Showcase."
            )
        }

        return ItemHealth(
            level: .healthy,
            badge: "Healthy",
            detail: "Project code, AppIcon art, and UI screenshots all present."
        )
    }

    /// Comprehensive health and wallpaper art inspection of a theme in ~/.config/summon/themes/<slug>.
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

        // --- ART INSPECTION: WALLPAPERS ---
        if theme.wallpapers.isEmpty {
            return ItemHealth(
                level: .warning,
                badge: "No Wallpaper",
                detail: "Theme has no wallpaper images configured or generated.",
                fixPrompt: "Theme '\(theme.name)' (slug: \(theme.slug)) in \(folder.path) has no wallpaper images. Generate a wallpaper image matching the theme using summon-art skill (wallpapers.md), save it to \(folder.path), and update theme.json."
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
            detail: "Theme JSON, wallpaper art assets, and contrast checks pass."
        )
    }

    /// Scans art jobs in ~/Summon/Art.
    public static func scanArtJobs(
        artFolder: URL,
        fileManager: FileManager = .default
    ) -> [ArtJob] {
        guard let items = try? fileManager.contentsOfDirectory(atPath: artFolder.path) else { return [] }
        var jobs: [ArtJob] = []
        for item in items.sorted() where item != "antigravity-originals" && !item.hasPrefix(".") {
            let jobFolder = artFolder.appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: jobFolder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = (try? fileManager.contentsOfDirectory(atPath: jobFolder.path))?
                .filter { !$0.hasPrefix(".") }
                .sorted() ?? []
            let images = files.filter {
                let lower = $0.lowercased()
                return lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".webp") || lower.hasSuffix(".icns")
            }
            let kind: ArtJob.Kind = item.hasPrefix("icon-") ? .icon : (item.contains("wallpaper") ? .wallpaper : .general)
            jobs.append(ArtJob(name: item, path: jobFolder.path, images: images, kind: kind))
        }
        return jobs
    }

    /// Inspects an art job in ~/Summon/Art/<job>.
    public static func check(
        artJob: ArtJob,
        fileManager: FileManager = .default
    ) -> ItemHealth {
        if artJob.images.isEmpty {
            return ItemHealth(
                level: .warning,
                badge: "Empty Job",
                detail: "No generated candidate images in ~/Summon/Art/\(artJob.name).",
                fixPrompt: "Art job '\(artJob.name)' in ~/Summon/Art/\(artJob.name) has no generated images. Use summon-art skill to generate 3 direction candidates (place, material, abstract)."
            )
        }

        if artJob.kind == .icon {
            let hasIcns = artJob.images.contains { $0.hasSuffix(".icns") }
            if !hasIcns {
                return ItemHealth(
                    level: .warning,
                    badge: "No ICNS",
                    detail: "\(artJob.images.count) candidate(s), but AppIcon.icns is not compiled yet.",
                    fixPrompt: "Compile AppIcon.icns from candidates in ~/Summon/Art/\(artJob.name) and install it to the app's Resources/ folder."
                )
            }
        }

        return ItemHealth(
            level: .healthy,
            badge: "\(artJob.images.count) image\(artJob.images.count == 1 ? "" : "s")",
            detail: "\(artJob.images.count) candidate image(s) ready in ~/Summon/Art/\(artJob.name)."
        )
    }
}
