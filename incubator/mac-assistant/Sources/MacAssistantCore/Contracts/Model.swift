import Foundation

// Provider-neutral model interface. The model proposes structured output (hypotheses citing
// evidence, next steps naming registered tools); the coordinator and policy broker decide what runs.
// Changing the model never changes what an operation is allowed to do.

public enum ModelLocality: String, Sendable, Hashable, Codable {
    case local
    case cloud
}

public struct ModelMessage: Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Hashable, Codable { case user, assistant }
    public var role: Role
    public var text: String

    public init(_ role: Role, _ text: String) {
        self.role = role
        self.text = text
    }
}

public struct ModelRequest: Sendable, Hashable {
    public var system: String
    public var messages: [ModelMessage]
    /// When set, the reply's `structured` value must validate against it.
    public var responseSchema: Schema?
    public var maxOutputTokens: Int

    public init(system: String, messages: [ModelMessage], responseSchema: Schema? = nil, maxOutputTokens: Int = 1024) {
        self.system = system
        self.messages = messages
        self.responseSchema = responseSchema
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct TokenUsage: Sendable, Hashable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct ModelReply: Sendable, Hashable {
    public var text: String
    public var structured: JSONValue?
    public var usage: TokenUsage?
    /// The model id that actually answered.
    public var model: String

    public init(text: String, structured: JSONValue? = nil, usage: TokenUsage? = nil, model: String) {
        self.text = text
        self.structured = structured
        self.usage = usage
        self.model = model
    }
}

public enum ModelAvailability: Sendable, Hashable {
    case available
    /// Reason shown to the user ("Apple Intelligence is off", "No API key in Keychain").
    case unavailable(String)
}

/// One model backend. Implementations live in `Models/`; the coordinator only sees this.
public struct ModelAdapter: Sendable {
    public var id: String
    public var displayName: String
    public var locality: ModelLocality
    public var availability: @Sendable () async -> ModelAvailability
    public var complete: @Sendable (ModelRequest) async throws -> ModelReply
    /// Upper-bound cost estimate in USD for the export preview; nil for local models.
    public var estimateCostUSD: @Sendable (ModelRequest) -> Double?

    public init(
        id: String,
        displayName: String,
        locality: ModelLocality,
        availability: @escaping @Sendable () async -> ModelAvailability,
        complete: @escaping @Sendable (ModelRequest) async throws -> ModelReply,
        estimateCostUSD: @escaping @Sendable (ModelRequest) -> Double? = { _ in nil }
    ) {
        self.id = id
        self.displayName = displayName
        self.locality = locality
        self.availability = availability
        self.complete = complete
        self.estimateCostUSD = estimateCostUSD
    }
}
