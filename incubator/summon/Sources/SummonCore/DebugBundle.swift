import Foundation

/// `summon debug`: one text file with what an agent (or a person) needs to start on a problem.
/// The unified log is huge, so it is always time-boxed and filtered to errors.
public struct DebugBundle: Sendable {
    public struct Section: Sendable, Equatable {
        public let title: String
        public let plan: LaunchPlan
    }

    public let paths: SummonPaths
    public let runner: Runner
    public let brewPath: String?
    public let macctlPath: String?

    public init(paths: SummonPaths, runner: @escaping Runner, brewPath: String?, macctlPath: String?) {
        self.paths = paths
        self.runner = runner
        self.brewPath = brewPath
        self.macctlPath = macctlPath
    }

    public func sections(logWindow: String = "1h") -> [Section] {
        var result: [Section] = [
            Section(title: "macOS VERSION", plan: LaunchPlan(executable: "/usr/bin/sw_vers", arguments: [])),
            Section(title: "HARDWARE", plan: LaunchPlan(executable: "/usr/sbin/system_profiler", arguments: ["SPHardwareDataType"])),
            Section(title: "UNIFIED LOG (ERRORS, LAST \(logWindow))", plan: LaunchPlan(
                executable: "/usr/bin/log",
                arguments: ["show", "--last", logWindow, "--predicate", "messageType == error", "--style", "compact"]
            )),
        ]
        for dir in paths.diagnosticReportDirs {
            result.append(Section(title: "DIAGNOSTIC REPORTS (\(dir.path))", plan: LaunchPlan(executable: "/bin/ls", arguments: ["-lt", dir.path])))
        }
        if let brewPath {
            result.append(Section(title: "HOMEBREW PACKAGES", plan: LaunchPlan(executable: brewPath, arguments: ["list", "--versions"])))
        }
        if let macctlPath {
            result.append(Section(title: "MACCTL DOCTOR", plan: LaunchPlan(executable: macctlPath, arguments: ["doctor"])))
        }
        return result
    }

    /// Runs every section; a failing one is recorded in place rather than aborting the bundle.
    public func collect(logWindow: String = "1h", now: Date = Date(), maxLinesPerSection: Int = 400) async -> String {
        let formatter = ISO8601DateFormatter()
        var text = "Summon debug bundle\nDate: \(formatter.string(from: now))\nRedaction is best effort. Review before sharing.\n"
        for section in sections(logWindow: logWindow) {
            text += "\n=========================================\n\(section.title)\n=========================================\n"
            do {
                let output = try await runner(section.plan.executable, section.plan.arguments)
                text += Self.truncate(DebugRedactor.redact(output, home: paths.home.path), maxLines: maxLinesPerSection)
            } catch {
                text += DebugRedactor.redact("(failed: \(error))\n", home: paths.home.path)
            }
        }
        return text
    }

    /// Exported bundles use an atomic, owner-only file rather than ambient umask permissions.
    public static func save(_ text: String, to file: URL) throws { try TextFile.write(text, to: file) }

    /// Keeps the last `maxLines` lines, which for logs are the most recent.
    public static func truncate(_ text: String, maxLines: Int) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last == "" { lines.removeLast() }  // a trailing newline ends the last line; it is not a line
        guard lines.count > maxLines else { return text.hasSuffix("\n") ? text : text + "\n" }
        let kept = lines.suffix(maxLines).joined(separator: "\n")
        return "(\(lines.count - maxLines) earlier lines omitted)\n" + kept + (kept.hasSuffix("\n") ? "" : "\n")
    }
}

/// `~/.config/summon/hooks/<event>.d/`: every executable file runs, in name order, with the event's arguments.
public enum HookEvent: String, Sendable, CaseIterable {
    case themeSet = "theme-set"
    case postLogin = "post-login"
    case postUpdate = "post-update"
    case wake = "wake"
    case crash = "crash"
}

public struct HookRunner: Sendable {
    public let paths: SummonPaths
    public let runner: Runner

    public init(paths: SummonPaths, runner: @escaping Runner) {
        self.paths = paths
        self.runner = runner
    }

    public func scripts(for event: HookEvent) -> [URL] {
        let dir = paths.hooks.appendingPathComponent("\(event.rawValue).d", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items
            .filter { !$0.lastPathComponent.hasPrefix(".") && FileManager.default.isExecutableFile(atPath: $0.path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Runs every hook; returns one line per hook that failed.
    public func run(_ event: HookEvent, arguments: [String]) async -> [String] {
        var failures: [String] = []
        for script in scripts(for: event) {
            do {
                _ = try await runner(script.path, arguments)
            } catch {
                failures.append("\(script.lastPathComponent): \(error)")
            }
        }
        return failures
    }
}
