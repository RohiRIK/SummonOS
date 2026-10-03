import Foundation

/// A request to run one tool. Everything here comes from an untrusted source (a model, a skill, an
/// MCP client) until the policy broker has checked it.
public struct InvocationRequest: Sendable, Hashable {
    public var tool: ToolID
    /// The version the plan was made against. A different registered version invalidates the plan.
    public var version: Version
    public var input: JSONValue
    /// Required for any effect above `.read`.
    public var authorization: Authorization?

    public init(tool: ToolID, version: Version, input: JSONValue = [:], authorization: Authorization? = nil) {
        self.tool = tool
        self.version = version
        self.input = input
        self.authorization = authorization
    }
}

/// Consent bound to one exact operation: tool, version, canonical input digest, and targets.
/// Any difference at execution time (changed target, new tool version) invalidates it.
public struct Authorization: Sendable, Hashable, Codable {
    public var id: UUID
    public var tool: ToolID
    public var version: Version
    /// SHA-256 hex of `JSONValue.canonicalData()` of the approved input.
    public var inputDigest: String
    public var targets: [ResourceTarget]
    public var effect: Effect
    public var grantedAt: Date
    public var expiresAt: Date

    public init(id: UUID = UUID(), tool: ToolID, version: Version, inputDigest: String,
                targets: [ResourceTarget], effect: Effect, grantedAt: Date, expiresAt: Date)
    {
        self.id = id
        self.tool = tool
        self.version = version
        self.inputDigest = inputDigest
        self.targets = targets
        self.effect = effect
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }
}

/// Why the broker refused. Every refusal happens before the tool's `run` is called.
public enum PolicyDenial: Error, Sendable, Hashable, CustomStringConvertible {
    case unknownTool(ToolID)
    case versionMismatch(ToolID, requested: Version, registered: Version)
    case invalidInput(ToolID, problems: [String])
    case unsupportedOS(ToolID, minimum: Version, actual: Version)
    case missingCapability(ToolID, Capability)
    case outOfScope(ToolID, ResourceTarget)
    case authorizationRequired(ToolID, Effect)
    case authorizationMismatch(ToolID, reason: String)
    case authorizationExpired(ToolID)
    case invalidOutput(ToolID, problems: [String])

    public var description: String {
        switch self {
        case .unknownTool(let tool): "Unknown tool \(tool)"
        case .versionMismatch(let tool, let requested, let registered):
            "\(tool) is version \(registered), the plan expected \(requested)"
        case .invalidInput(let tool, let problems): "Invalid input for \(tool): \(problems.joined(separator: "; "))"
        case .unsupportedOS(let tool, let minimum, let actual): "\(tool) needs macOS \(minimum), this Mac runs \(actual)"
        case .missingCapability(let tool, let capability): "\(tool) needs the \(capability.rawValue) permission"
        case .outOfScope(let tool, let target): "\(tool) may not touch \(target)"
        case .authorizationRequired(let tool, let effect): "\(tool) makes a \(effect.rawValue) and needs approval"
        case .authorizationMismatch(let tool, let reason): "Approval for \(tool) no longer matches: \(reason)"
        case .authorizationExpired(let tool): "Approval for \(tool) expired"
        case .invalidOutput(let tool, let problems): "\(tool) returned invalid output: \(problems.joined(separator: "; "))"
        }
    }
}
