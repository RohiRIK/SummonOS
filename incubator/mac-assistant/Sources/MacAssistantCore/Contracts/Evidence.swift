import Foundation

public struct EvidenceID: RawRepresentable, Hashable, Comparable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    public static func < (lhs: EvidenceID, rhs: EvidenceID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How careful to be with a value: what may be logged, journaled in full, or sent to a cloud model.
public enum Sensitivity: String, Sendable, Hashable, Codable, Comparable, CaseIterable {
    /// Counts, percentages, sizes. Safe to log and export.
    case low
    /// Process names, paths, hostnames, app names. Journal locally; redact before export unless the
    /// user approves it in the export preview.
    case personal
    /// Tokens, passwords, keys. Never stored, logged, or exported.
    case secret

    public static func < (lhs: Sensitivity, rhs: Sensitivity) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One measured fact, with where and when it came from. Claims shown to the user must cite these.
public struct Evidence: Sendable, Hashable, Codable, Identifiable {
    public var id: EvidenceID
    public var tool: ToolID
    public var toolVersion: Version
    public var collectedAt: Date
    /// Short label: "Memory pressure", "Free space on Macintosh HD".
    public var title: String
    /// One plain sentence with the measured value: "Swap used: 6.2 GB of 7.0 GB".
    public var summary: String
    public var value: JSONValue
    public var sensitivity: Sensitivity
    /// Collection limits a reader must know: "top 15 processes by CPU only", "output truncated at 64 KB".
    public var limits: [String]

    public init(
        id: EvidenceID,
        tool: ToolID,
        toolVersion: Version,
        collectedAt: Date,
        title: String,
        summary: String,
        value: JSONValue,
        sensitivity: Sensitivity = .low,
        limits: [String] = []
    ) {
        self.id = id
        self.tool = tool
        self.toolVersion = toolVersion
        self.collectedAt = collectedAt
        self.title = title
        self.summary = summary
        self.value = value
        self.sensitivity = sensitivity
        self.limits = limits
    }
}

/// Why some evidence could not be collected. Shown to the user; never hidden.
public struct CollectionIssue: Sendable, Hashable, Codable {
    public enum Reason: Sendable, Hashable, Codable {
        case permissionDenied(Capability)
        case unsupportedOS(Version)
        case timedOut
        case cancelled
        case failed(String)
    }

    public var tool: ToolID
    public var reason: Reason

    public init(tool: ToolID, reason: Reason) {
        self.tool = tool
        self.reason = reason
    }
}

/// A deterministic rule's conclusion from evidence. The model may explain findings; it may not
/// invent ones without evidence.
public struct Finding: Sendable, Hashable, Codable, Identifiable {
    public enum Severity: String, Sendable, Hashable, Codable, Comparable, CaseIterable {
        case info, attention, problem

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    /// Whether the condition lasted across samples. A single high-CPU sample is `unknown`, not faulty.
    public enum Persistence: String, Sendable, Hashable, Codable {
        case transient, persistent, unknown
    }

    /// Rule id, stable across runs: "memory.pressure.high".
    public var id: String
    public var title: String
    public var detail: String
    public var severity: Severity
    public var persistence: Persistence
    public var evidence: [EvidenceID]
    /// A specific next step, or nil when more evidence is needed first.
    public var nextStep: String?

    public init(
        id: String,
        title: String,
        detail: String,
        severity: Severity,
        persistence: Persistence,
        evidence: [EvidenceID],
        nextStep: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.persistence = persistence
        self.evidence = evidence
        self.nextStep = nextStep
    }
}
