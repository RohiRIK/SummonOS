import Foundation

/// Immutable identity of this build: plain data copied from the compiled `SummonVersion` constants, so showing it
/// never touches the filesystem, the network or the updater.
public struct BuildInfo: Equatable, Sendable {
    public static let unknown = "unknown"

    public let marketingVersion: String
    public let buildNumber: String
    public let sourceRevision: String
    /// "clean", "dirty" or "unidentified": why `sourceRevision` is or is not a commit.
    public let sourceState: String
    public let channel: String
    public let configuration: String
    public let buildTimestamp: String

    public init(marketingVersion: String, buildNumber: String, sourceRevision: String,
                sourceState: String, channel: String, configuration: String, buildTimestamp: String) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.sourceRevision = sourceRevision
        self.sourceState = sourceState
        self.channel = channel
        self.configuration = configuration
        self.buildTimestamp = buildTimestamp
    }

    public static let current = BuildInfo(
        marketingVersion: SummonVersion.marketingVersion, buildNumber: SummonVersion.buildNumber,
        sourceRevision: SummonVersion.sourceRevision, sourceState: SummonVersion.sourceState, channel: SummonVersion.channel,
        configuration: SummonVersion.configuration, buildTimestamp: SummonVersion.buildTimestamp)

    /// Short revision for display (12 characters); nil when the build does not know its source.
    public var shortRevision: String? {
        let revision = sourceRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty, revision.lowercased() != Self.unknown else { return nil }
        return String(revision.prefix(12))
    }

    /// The build instant, or nil when the timestamp is "unknown" or not ISO 8601.
    public var builtAt: Date? {
        guard buildTimestamp.first?.isNumber == true else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: buildTimestamp) { return date }
        plain.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: buildTimestamp)
    }

    /// "2026-11-08 12:00 UTC"; absolute and zone-stable so a screenshot or report reads the same everywhere.
    public var builtAtText: String {
        guard let date = builtAt else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }

    public var channelText: String { channel.isEmpty ? "Unknown" : channel.prefix(1).uppercased() + channel.dropFirst() }
    public var configurationText: String {
        configuration.isEmpty ? "Unknown" : configuration.prefix(1).uppercased() + configuration.dropFirst()
    }

    /// Revision text; an unknown revision says why when the build knows.
    public var sourceText: String {
        if let short = shortRevision { return sourceState == "dirty" ? "\(short) (dirty working tree)" : short }
        return sourceState == "dirty" ? "Unknown (dirty working tree)" : "Unknown"
    }

    /// Labeled fields in display order, shared by every About surface. Unknown values are said, never invented.
    public var fields: [(label: String, value: String)] {
        [("Version", marketingVersion),
         ("Build", buildNumber),
         ("Source revision", sourceText),
         ("Channel", channelText),
         ("Configuration", configurationText),
         ("Built", builtAtText)]
    }
}
