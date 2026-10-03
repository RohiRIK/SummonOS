import Foundation

/// The JSON Schema subset tools declare for inputs and outputs. It encodes as standard JSON Schema,
/// so the same value is shown to a model and enforced by the policy broker (`SchemaValidator`).
///
/// Supported keywords: type, description, properties, required, additionalProperties (boolean),
/// items, enum, minimum, maximum, minLength, maxLength, maxItems, pattern.
public struct Schema: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case object, array, string, number, integer, boolean, null
    }

    public var type: Kind
    public var description: String?
    public var properties: [String: Schema]?
    public var required: [String]?
    /// `nil` is treated as `false`: tool inputs reject unknown keys unless a schema opts in.
    public var additionalProperties: Bool?
    public var items: Indirect<Schema>?
    public var enumValues: [JSONValue]?
    public var minimum: Double?
    public var maximum: Double?
    public var minLength: Int?
    public var maxLength: Int?
    public var maxItems: Int?
    /// Anchored regular expression the whole string must match.
    public var pattern: String?

    enum CodingKeys: String, CodingKey {
        case type, description, properties, required, additionalProperties, items
        case enumValues = "enum"
        case minimum, maximum, minLength, maxLength, maxItems, pattern
    }

    public init(
        type: Kind,
        description: String? = nil,
        properties: [String: Schema]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil,
        items: Schema? = nil,
        enumValues: [JSONValue]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        maxItems: Int? = nil,
        pattern: String? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
        self.items = items.map(Indirect.init)
        self.enumValues = enumValues
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.maxItems = maxItems
        self.pattern = pattern
    }

    // MARK: Builders

    public static func object(
        _ properties: [String: Schema], required: [String] = [], description: String? = nil
    ) -> Schema {
        Schema(type: .object, description: description, properties: properties, required: required,
               additionalProperties: false)
    }

    public static func array(of items: Schema, maxItems: Int? = nil, description: String? = nil) -> Schema {
        Schema(type: .array, description: description, items: items, maxItems: maxItems)
    }

    public static func string(
        _ description: String? = nil, maxLength: Int? = nil, pattern: String? = nil, oneOf values: [String]? = nil
    ) -> Schema {
        Schema(type: .string, description: description, enumValues: values?.map(JSONValue.string),
               maxLength: maxLength, pattern: pattern)
    }

    public static func integer(_ description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> Schema {
        Schema(type: .integer, description: description, minimum: minimum, maximum: maximum)
    }

    public static func number(_ description: String? = nil, minimum: Double? = nil, maximum: Double? = nil) -> Schema {
        Schema(type: .number, description: description, minimum: minimum, maximum: maximum)
    }

    public static func boolean(_ description: String? = nil) -> Schema {
        Schema(type: .boolean, description: description)
    }

    /// Input of a tool that takes no arguments: `{}` only.
    public static let empty = Schema.object([:])
}

/// Heap box so a value type can contain itself (`Schema.items`). Encodes as the wrapped value.
public final class Indirect<Value: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    public let value: Value

    public init(_ value: Value) { self.value = value }

    public init(from decoder: any Decoder) throws {
        value = try decoder.singleValueContainer().decode(Value.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func == (lhs: Indirect, rhs: Indirect) -> Bool { lhs.value == rhs.value }
    public func hash(into hasher: inout Hasher) { hasher.combine(value) }
}
