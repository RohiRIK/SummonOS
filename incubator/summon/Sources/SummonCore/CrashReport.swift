import Foundation

/// A macOS `.ips` diagnostic report: one JSON header line, then (for crashes) a JSON body.
public struct CrashReport: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case crash, hang, panic, other
    }

    public var id: String { file }
    public var file: String
    public var kind: Kind
    public var bugType: String
    public var appName: String
    public var appVersion: String?
    public var timestamp: String?
    public var incidentID: String?
    public var osVersion: String?
    public var process: String?
    public var pid: Int?
    public var exceptionType: String?
    public var signal: String?
    /// Symbols of the top frames of the crashed thread, when the body has them.
    public var topFrames: [String]

    public init(file: String, kind: Kind, bugType: String, appName: String, appVersion: String?, timestamp: String?,
                incidentID: String?, osVersion: String?, process: String?, pid: Int?, exceptionType: String?,
                signal: String?, topFrames: [String]) {
        self.file = file
        self.kind = kind
        self.bugType = bugType
        self.appName = appName
        self.appVersion = appVersion
        self.timestamp = timestamp
        self.incidentID = incidentID
        self.osVersion = osVersion
        self.process = process
        self.pid = pid
        self.exceptionType = exceptionType
        self.signal = signal
        self.topFrames = topFrames
    }

    /// The name used for display and for muting: the process name when known, else the app name.
    public var program: String { process ?? appName }

    public enum ParseError: Error, Equatable, Sendable {
        case emptyFile
        case badHeader
    }

    public static func parse(_ text: String, file: String) throws -> CrashReport {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.emptyFile }

        let headerLine: Substring
        let bodyText: Substring
        if let newline = trimmed.firstIndex(of: "\n") {
            headerLine = trimmed[..<newline]
            bodyText = trimmed[trimmed.index(after: newline)...]
        } else {
            headerLine = trimmed[...]
            bodyText = ""
        }

        guard let header = jsonObject(String(headerLine)) else { throw ParseError.badHeader }

        let bugType = string(header["bug_type"]) ?? "unknown"
        let name = string(header["app_name"]) ?? string(header["name"]) ?? ((file as NSString).lastPathComponent)
        var report = CrashReport(
            file: file,
            kind: kind(for: bugType),
            bugType: bugType,
            appName: name,
            appVersion: string(header["app_version"]),
            timestamp: string(header["timestamp"]),
            incidentID: string(header["incident_id"]),
            osVersion: string(header["os_version"]),
            process: nil,
            pid: nil,
            exceptionType: nil,
            signal: nil,
            topFrames: []
        )

        // Hang and panic bodies are often plain text; a body that is not JSON just leaves the details empty.
        if let body = jsonObject(String(bodyText)) {
            report.process = string(body["procName"])
            report.pid = int(body["pid"])
            if let exception = body["exception"] as? [String: Any] {
                report.exceptionType = string(exception["type"])
                report.signal = string(exception["signal"])
            }
            report.topFrames = crashedThreadFrames(body, limit: 8)
        }
        return report
    }

    static func kind(for bugType: String) -> Kind {
        switch bugType {
        case "309": return .crash
        case "298", "288": return .hang
        case "210": return .panic
        default: return .other
        }
    }

    private static func crashedThreadFrames(_ body: [String: Any], limit: Int) -> [String] {
        guard let threads = body["threads"] as? [[String: Any]], !threads.isEmpty else { return [] }
        let index = int(body["faultingThread"]) ?? threads.firstIndex(where: { ($0["triggered"] as? Bool) == true }) ?? 0
        guard index >= 0, index < threads.count, let frames = threads[index]["frames"] as? [[String: Any]] else { return [] }
        let images = body["usedImages"] as? [[String: Any]] ?? []
        var result: [String] = []
        for frame in frames.prefix(limit) {
            let symbol = string(frame["symbol"]) ?? "???"
            var imageName = ""
            if let imageIndex = int(frame["imageIndex"]), imageIndex >= 0, imageIndex < images.count {
                imageName = string(images[imageIndex]["name"]) ?? ""
            }
            result.append(imageName.isEmpty ? symbol : "\(imageName): \(symbol)")
        }
        return result
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

/// Finds reports written since the last scan and remembers which programs the user muted.
public struct CrashWatcher: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    public func marker() -> Date? {
        guard let line = TextFile.firstLine(paths.crashMarkerFile), let seconds = Double(line) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public func saveMarker(_ date: Date) throws {
        try TextFile.write(String(date.timeIntervalSince1970) + "\n", to: paths.crashMarkerFile)
    }

    public func muted() -> Set<String> {
        guard let text = TextFile.read(paths.crashMutedFile) else { return [] }
        let names = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Set(names)
    }

    public func setMuted(_ program: String, muted isMuted: Bool) throws {
        var names = muted()
        let key = Self.muteKey(program)
        if isMuted { names.insert(key) } else { names.remove(key) }
        try TextFile.write(names.sorted().map { $0 + "\n" }.joined(), to: paths.crashMutedFile)
    }

    /// Paths are muted by their last component, so `/usr/bin/foo` and `foo` are the same program.
    public static func muteKey(_ program: String) -> String {
        (program as NSString).lastPathComponent
    }

    /// `.ips` files in the report folders, newest first, optionally only those modified after `since`.
    public func reportFiles(since: Date?) -> [URL] {
        var found: [(URL, Date)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for dir in paths.diagnosticReportDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { continue }
            for url in items where url.pathExtension == "ips" {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile ?? true else { continue }
                let modified = values?.contentModificationDate ?? .distantPast
                if let since, modified <= since { continue }
                found.append((url, modified))
            }
        }
        return found.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    /// Parsed reports, newest first, skipping muted programs and unreadable files.
    public func reports(since: Date?, limit: Int = 20) -> [CrashReport] {
        let mutedNames = muted()
        var result: [CrashReport] = []
        for url in reportFiles(since: since) {
            guard result.count < limit else { break }
            guard let text = TextFile.read(url), let report = try? CrashReport.parse(text, file: url.path) else { continue }
            if mutedNames.contains(Self.muteKey(report.program)) || mutedNames.contains(Self.muteKey(report.appName)) {
                continue
            }
            result.append(report)
        }
        return result
    }
}

/// The task handed to the agent when the user clicks Diagnose. The method lives in the
/// `diagnose-crash-mac` skill so it is edited in one place and works with any agent.
public enum DiagnosePrompt {
    public static func make(for report: CrashReport, skillPath: String) -> String {
        var lines: [String] = []
        let what: String
        switch report.kind {
        case .crash: what = "A program crashed"
        case .hang: what = "A program hung"
        case .panic: what = "The Mac had a kernel panic"
        case .other: what = "macOS wrote a diagnostic report"
        }
        lines.append("\(what) on this Mac and I want to know why.")
        lines.append("")
        lines.append("What macOS recorded:")
        lines.append("  program:   \(report.program)")
        if let version = report.appVersion { lines.append("  version:   \(version)") }
        if let pid = report.pid { lines.append("  PID:       \(pid)") }
        if let type = report.exceptionType { lines.append("  exception: \(type)") }
        if let signal = report.signal { lines.append("  signal:    \(signal)") }
        if let time = report.timestamp { lines.append("  time:      \(time)") }
        if let os = report.osVersion { lines.append("  macOS:     \(os)") }
        lines.append("  report:    \(report.file)")
        lines.append("")
        lines.append("Use the diagnose-crash-mac skill: it covers how to investigate, what to report, and")
        lines.append("when a crash is worth reporting upstream. If your harness has no skill mechanism,")
        lines.append("read the skill file directly and follow it instead:")
        lines.append("")
        lines.append("  \(skillPath)")
        return lines.joined(separator: "\n")
    }
}
