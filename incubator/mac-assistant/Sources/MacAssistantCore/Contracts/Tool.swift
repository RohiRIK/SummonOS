import Foundation

// The execution contract. A tool is a small bounded operation with typed input and output. Skills
// and model output never grant permissions: the policy broker checks every invocation against the
// trusted descriptor registered here, not against anything a plugin or model claims.

public struct ToolID: RawRepresentable, Hashable, Comparable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
    public static func < (lhs: ToolID, rhs: ToolID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// `major.minor.patch`. Used for tool versions and macOS versions.
public struct Version: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses "15", "15.4", or "15.4.1". Returns nil for anything else.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        self.init(numbers[0], numbers.count > 1 ? numbers[1] : 0, numbers.count > 2 ? numbers[2] : 0)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let version = Version(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad version \(string)")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// What an invocation can do to the Mac. Ordered from least to most impact.
public enum Effect: String, Sendable, Hashable, Codable, Comparable, CaseIterable {
    /// Reads state only. Runs within the user's task and granted scope.
    case read
    /// Changes a setting and can restore the prior value. Needs task-scoped consent.
    case reversibleChange
    /// Installs, removes, or interrupts something; recovery may be partial. Needs specific approval.
    case change
    /// Needs administrator rights. Needs specific approval bound to target and arguments.
    case privileged

    public static func < (lhs: Effect, rhs: Effect) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// macOS permissions and resources a tool needs. Checked again immediately before execution.
public enum Capability: String, Sendable, Hashable, Codable, CaseIterable {
    case fullDiskAccess
    case accessibility
    case automation
    case location
    /// Makes network requests of its own (DNS lookups, connectivity probes).
    case network
    case administrator
}

/// One concrete thing an invocation touches, derived from its validated input.
public enum ResourceTarget: Sendable, Hashable, Codable, CustomStringConvertible {
    /// Machine-wide statistics (load, memory, process table, volumes). Read-only by nature.
    case systemStatistics
    case path(String)
    case preference(domain: String, key: String)
    case host(String)
    case application(bundleID: String)

    public var description: String {
        switch self {
        case .systemStatistics: "system statistics"
        case .path(let path): "path \(path)"
        case .preference(let domain, let key): "preference \(domain) \(key)"
        case .host(let host): "host \(host)"
        case .application(let bundleID): "app \(bundleID)"
        }
    }
}

/// Everything a tool may touch. An invocation whose targets fall outside it is denied.
public struct ResourceScope: Sendable, Hashable, Codable {
    public var systemStatistics: Bool
    /// Absolute path prefixes, compared by path component (`/Users/a` does not contain `/Users/ab`).
    /// `~` is expanded by the broker against the current user's home directory.
    public var pathPrefixes: [String]
    public var preferences: [PreferenceKey]
    public var hosts: [String]
    public var applications: [String]

    public struct PreferenceKey: Sendable, Hashable, Codable {
        public var domain: String
        public var key: String
        public init(domain: String, key: String) {
            self.domain = domain
            self.key = key
        }
    }

    public init(
        systemStatistics: Bool = false,
        pathPrefixes: [String] = [],
        preferences: [PreferenceKey] = [],
        hosts: [String] = [],
        applications: [String] = []
    ) {
        self.systemStatistics = systemStatistics
        self.pathPrefixes = pathPrefixes
        self.preferences = preferences
        self.hosts = hosts
        self.applications = applications
    }

    public static let systemStatisticsOnly = ResourceScope(systemStatistics: true)
}

/// What recovery an operation honestly offers. Never promise universal rollback.
public struct RecoveryContract: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        /// Read-only: nothing to recover.
        case notApplicable
        /// The prior value is stored and can be written back, then verified.
        case restorePriorValue
        /// Recovery is partial (for example reinstalling an app does not bring back deleted data).
        case partial
        /// No recovery. The preview must say so.
        case none
    }

    public var kind: Kind
    /// Plain-language limits shown in the preview.
    public var limits: String

    public init(_ kind: Kind, limits: String = "") {
        self.kind = kind
        self.limits = limits
    }

    public static let notApplicable = RecoveryContract(.notApplicable)
}

/// The trusted declaration of a tool. Lives in the registry; checked on every invocation.
public struct ToolDescriptor: Sendable, Hashable, Codable, Identifiable {
    public var id: ToolID
    public var version: Version
    /// One line for people and models: what it does, not how.
    public var summary: String
    public var input: Schema
    public var output: Schema
    public var minimumOS: Version
    /// Newest macOS the tool was tested on; newer systems run it but the UI flags it as untested.
    public var testedThroughOS: Version?
    public var capabilities: Set<Capability>
    public var effect: Effect
    public var scope: ResourceScope
    public var timeoutSeconds: Double
    /// True when cancelling mid-run leaves the system unchanged.
    public var cancellable: Bool
    /// How success is checked after running (for read tools: what makes the output trustworthy).
    public var verification: String
    public var recovery: RecoveryContract

    public init(
        id: ToolID,
        version: Version,
        summary: String,
        input: Schema = .empty,
        output: Schema,
        minimumOS: Version = Version(15),
        testedThroughOS: Version? = nil,
        capabilities: Set<Capability> = [],
        effect: Effect,
        scope: ResourceScope,
        timeoutSeconds: Double,
        cancellable: Bool = true,
        verification: String,
        recovery: RecoveryContract = .notApplicable
    ) {
        self.id = id
        self.version = version
        self.summary = summary
        self.input = input
        self.output = output
        self.minimumOS = minimumOS
        self.testedThroughOS = testedThroughOS
        self.capabilities = capabilities
        self.effect = effect
        self.scope = scope
        self.timeoutSeconds = timeoutSeconds
        self.cancellable = cancellable
        self.verification = verification
        self.recovery = recovery
    }
}

/// What the Mac looks like right now, rechecked immediately before each execution.
public struct HostInfo: Sendable, Hashable {
    public var osVersion: Version
    public var grantedCapabilities: Set<Capability>
    public var homeDirectory: String

    public init(osVersion: Version, grantedCapabilities: Set<Capability>, homeDirectory: String) {
        self.osVersion = osVersion
        self.grantedCapabilities = grantedCapabilities
        self.homeDirectory = homeDirectory
    }
}

/// Side effects a tool may use, injected so tests pass fakes and never touch the real system.
public struct ToolContext: Sendable {
    public var runner: CommandRunner
    public var now: @Sendable () -> Date

    public init(runner: CommandRunner, now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.now = now
    }
}

public struct ToolResult: Sendable, Hashable {
    /// Validated by the broker against `descriptor.output` before it reaches the workflow or a model.
    public var output: JSONValue
    public var evidence: [Evidence]
    public var issues: [CollectionIssue]

    public init(output: JSONValue, evidence: [Evidence] = [], issues: [CollectionIssue] = []) {
        self.output = output
        self.evidence = evidence
        self.issues = issues
    }
}

/// A runnable tool: the trusted descriptor plus its implementation.
public struct ToolDefinition: Sendable {
    public let descriptor: ToolDescriptor
    /// The concrete targets an already-validated input touches. The broker checks them against scope.
    public let targets: @Sendable (JSONValue) -> [ResourceTarget]
    public let run: @Sendable (JSONValue, ToolContext) async throws -> ToolResult

    public init(
        descriptor: ToolDescriptor,
        targets: @escaping @Sendable (JSONValue) -> [ResourceTarget] = { _ in [.systemStatistics] },
        run: @escaping @Sendable (JSONValue, ToolContext) async throws -> ToolResult
    ) {
        self.descriptor = descriptor
        self.targets = targets
        self.run = run
    }
}
