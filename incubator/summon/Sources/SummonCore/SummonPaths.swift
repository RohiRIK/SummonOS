import Foundation

/// Every file Summon reads or writes, rooted at one home folder so tests can use a temp dir.
public struct SummonPaths: Sendable, Equatable {
    public let home: URL
    /// Whether `/Library/Logs/DiagnosticReports` (machine-wide reports) is scanned too. Off in tests.
    public let includeSystemReports: Bool

    public init(home: URL, includeSystemReports: Bool = false) {
        self.home = home
        self.includeSystemReports = includeSystemReports
    }

    public static var live: SummonPaths {
        SummonPaths(home: FileManager.default.homeDirectoryForCurrentUser, includeSystemReports: true)
    }

    /// `~/.config`, which the agent may edit and which checkpoints commit when it is a git repo.
    public var userConfig: URL { home.appendingPathComponent(".config", isDirectory: true) }
    public var config: URL { userConfig.appendingPathComponent("summon", isDirectory: true) }
    public var defaultAgentFile: URL { config.appendingPathComponent("defaults/agent") }
    public var currentThemeFile: URL { config.appendingPathComponent("current-theme") }
    public var themes: URL { config.appendingPathComponent("themes", isDirectory: true) }
    public var generated: URL { config.appendingPathComponent("generated", isDirectory: true) }
    public var hooks: URL { config.appendingPathComponent("hooks", isDirectory: true) }
    public var menuFile: URL { config.appendingPathComponent("menu.jsonc") }

    /// Runtime state that is not configuration.
    public var state: URL { home.appendingPathComponent(".local/state/summon", isDirectory: true) }
    public var crashMarkerFile: URL { state.appendingPathComponent("crash-marker") }
    public var crashMutedFile: URL { state.appendingPathComponent("crash-muted") }

    public var work: URL { home.appendingPathComponent("Work", isDirectory: true) }

    /// Where macOS writes crash, hang and panic reports for this user and for the whole machine.
    public var diagnosticReportDirs: [URL] {
        var dirs = [home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)]
        if includeSystemReports {
            dirs.append(URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true))
        }
        return dirs
    }
}

/// Small text-file helpers shared by the stores.
enum TextFile {
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    static func firstLine(_ url: URL) -> String? {
        guard let text = read(url) else { return nil }
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
