import Foundation

/// Which problems the menu bar panel still shows. The panel is for what needs you now: a report leaves it after
/// 24 hours, once it was diagnosed, or when the user clears the list. Activity keeps the full history.
public struct ProblemArchive: Sendable {
    public static let maxAge: TimeInterval = 24 * 3600

    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    var file: URL { paths.state.appendingPathComponent("problems-archived.json") }

    public func archived() -> Set<String> {
        guard let data = try? Data(contentsOf: file),
              let files = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(files)
    }

    public func archive(_ files: [String]) throws {
        let all = archived().union(files).sorted()
        try TextFile.write(String(decoding: try JSONEncoder().encode(all), as: UTF8.self), to: file)
    }

    /// Reports not archived and not older than `maxAge`; a report with no readable date stays.
    public func visible(_ reports: [CrashReport], now: Date = Date()) -> [CrashReport] {
        let done = archived()
        return reports.filter { report in
            guard !done.contains(report.file) else { return false }
            guard let date = ActivityFeed.crashDate(report) else { return true }
            return now.timeIntervalSince(date) <= Self.maxAge
        }
    }
}
