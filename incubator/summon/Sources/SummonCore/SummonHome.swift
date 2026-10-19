import Foundation

/// `~/Summon`, the one place everything Summon and its agents make lives:
///
///     ~/Summon/
///     ├── Apps/     apps from the templates (each its own git repo)
///     ├── Art/      wallpaper and icon jobs, every candidate
///     ├── Themes -> ~/.config/summon/themes (where `summon theme set` reads them)
///     └── Tasks/    recurring task results, one folder per task
///
/// Generated parts stay out of git through `~/Summon/.gitignore`.
public enum SummonHome {
    static let gitignore = """
        # Summon's own folders: generated, never committed. Each app in Apps/ is its own repo with its own .gitignore.
        Art/
        Tasks/
        Showcase/
        Themes
        .DS_Store
        .build/
        build/
        .swiftpm/

        """

    /// Makes the folders, the Themes link and the .gitignore; leaves anything already there alone.
    public static func ensure(_ paths: SummonPaths) throws {
        let fm = FileManager.default
        for folder in [paths.apps, paths.art, paths.taskLogs] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try fm.createDirectory(at: paths.themes, withIntermediateDirectories: true)
        let link = paths.summonHome.appendingPathComponent("Themes")
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == nil, !fm.fileExists(atPath: link.path) {
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: paths.themes.path)
        }
        let ignore = paths.summonHome.appendingPathComponent(".gitignore")
        if !fm.fileExists(atPath: ignore.path) {
            try Data(gitignore.utf8).write(to: ignore, options: .atomic)
        }
    }

    /// Moves what older versions left elsewhere into `~/Summon`, once: art from `~/Downloads/summon-art` and
    /// `~/Downloads/summon-wallpapers`, task logs from `~/.local/state/summon/tasks`, and apps made straight in
    /// `~/Summon/<name>` (their registry paths follow). Never overwrites; returns what moved.
    @discardableResult
    public static func migrate(_ paths: SummonPaths) throws -> [String] {
        try ensure(paths)
        let fm = FileManager.default
        var moved: [String] = []

        func moveChildren(of source: URL, into destination: URL, rename: (String) -> String = { $0 }) throws {
            guard let names = try? fm.contentsOfDirectory(atPath: source.path) else { return }
            for name in names where name != ".DS_Store" {
                let target = destination.appendingPathComponent(rename(name))
                guard !fm.fileExists(atPath: target.path) else { continue }
                try fm.moveItem(at: source.appendingPathComponent(name), to: target)
                moved.append(target.path)
            }
            let left = (try? fm.contentsOfDirectory(atPath: source.path))?.filter { $0 != ".DS_Store" } ?? []
            if left.isEmpty { try? fm.removeItem(at: source) }
        }

        let downloads = paths.home.appendingPathComponent("Downloads", isDirectory: true)
        try moveChildren(of: downloads.appendingPathComponent("summon-art"), into: paths.art)
        try moveChildren(of: downloads.appendingPathComponent("summon-wallpapers"), into: paths.art) { "wallpaper-\($0)" }
        try moveChildren(of: paths.state.appendingPathComponent("tasks"), into: paths.taskLogs)

        // Apps from before Apps/ existed: registered projects sitting directly in ~/Summon.
        let store = ProjectStore(paths: paths)
        if var registry = try? store.load() {
            var changed = false
            for index in registry.projects.indices {
                let current = URL(fileURLWithPath: registry.projects[index].path)
                guard current.deletingLastPathComponent().standardizedFileURL == paths.summonHome.standardizedFileURL else { continue }
                let target = paths.apps.appendingPathComponent(current.lastPathComponent, isDirectory: true)
                guard fm.fileExists(atPath: current.path), !fm.fileExists(atPath: target.path) else { continue }
                try fm.moveItem(at: current, to: target)
                registry.projects[index].path = target.path
                moved.append(target.path)
                changed = true
            }
            if changed { try store.save(registry) }
        }
        return moved
    }
}
