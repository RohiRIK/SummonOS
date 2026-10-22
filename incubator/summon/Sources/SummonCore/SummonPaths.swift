import Darwin
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
    public var defaultTerminalFile: URL { config.appendingPathComponent("defaults/terminal") }
    public var agentSettingsFile: URL { config.appendingPathComponent("agents.json") }
    public var tasksFile: URL { config.appendingPathComponent("tasks.json") }
    /// One folder per recurring task, a log per run: `~/Summon/Tasks/<id>/`.
    public var taskLogs: URL { summonHome.appendingPathComponent("Tasks", isDirectory: true) }
    public var currentThemeFile: URL { config.appendingPathComponent("current-theme") }
    public var themes: URL { config.appendingPathComponent("themes", isDirectory: true) }
    public var generated: URL { config.appendingPathComponent("generated", isDirectory: true) }
    public var hooks: URL { config.appendingPathComponent("hooks", isDirectory: true) }
    public var menuFile: URL { config.appendingPathComponent("menu.jsonc") }
    /// Summon's private list of the projects it made. Stays on this Mac; never in plugins.json or a repo.
    public var projectRegistryFile: URL { config.appendingPathComponent("projects.json") }

    /// Runtime state that is not configuration.
    public var state: URL { home.appendingPathComponent(".local/state/summon", isDirectory: true) }
    public var crashMarkerFile: URL { state.appendingPathComponent("crash-marker") }
    public var crashMutedFile: URL { state.appendingPathComponent("crash-muted") }
    /// Summon's own activity log (agent sessions, themes, undos), JSON Lines, oldest first.
    public var eventLogFile: URL { state.appendingPathComponent("events.jsonl") }
    /// Written by the menu app on launch (pid, hotkeys, notification permission) for `summon doctor`.
    public var appHealthFile: URL { state.appendingPathComponent("app.json") }

    /// Where macctl keeps the snapshot it saves before every change, one `<id>.json` each.
    public var macctlSnapshots: URL {
        home.appendingPathComponent("Library/Application Support/macctl/snapshots", isDirectory: true)
    }

    /// `~/Summon`: the one home for everything Summon and its agents make; agents start here.
    public var summonHome: URL { home.appendingPathComponent("Summon", isDirectory: true) }
    /// Apps made from Summon's templates: `~/Summon/Apps/<name>`.
    public var apps: URL { summonHome.appendingPathComponent("Apps", isDirectory: true) }
    /// The folder new projects go in (the apps folder).
    public var projects: URL { apps }
    /// Art jobs (wallpapers, icons): every candidate in `~/Summon/Art/<job>/`.
    public var art: URL { summonHome.appendingPathComponent("Art", isDirectory: true) }

    /// Where macOS writes crash, hang and panic reports for this user and for the whole machine.
    public var diagnosticReportDirs: [URL] {
        var dirs = [home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)]
        if includeSystemReports {
            dirs.append(URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true))
        }
        return dirs
    }

    /// Where Summon's shared files live (themes, skills, wallpapers): `$SUMMON_PATH`, else `<binary>/../share/summon`,
    /// else the folder holding the binary.
    public static func installPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let explicit = environment["SUMMON_PATH"], !explicit.isEmpty {
            return (explicit as NSString).expandingTildeInPath
        }
        let binary = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        let binDir = binary.deletingLastPathComponent()
        let share = binDir.deletingLastPathComponent().appendingPathComponent("share/summon", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: share.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return share.path
        }
        return binDir.path
    }
}

/// Small text-file helpers shared by the stores.
enum TextFile {
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".summon-write-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: Data(text.utf8))
        try handle.synchronize()
        guard rename(temporary.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    static func firstLine(_ url: URL) -> String? {
        guard let text = read(url) else { return nil }
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
