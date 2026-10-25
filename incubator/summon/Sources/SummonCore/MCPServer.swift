import Foundation

/// Any JSON value, for the MCP wire format (no third-party JSON library).
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var int: Int? { if case .int(let value) = self { value } else { nil } }
    public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }

    /// Any `Encodable` as a JSON value (for `structuredContent`).
    public static func encoding<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// A stdio MCP server (JSON-RPC 2.0, one message per line): initialize, ping, tools and resources.
/// Transport-free so tests drive it line by line; `summon mcp` feeds it stdin.
public struct MCPServer: Sendable {
    public struct Tool: Sendable {
        public var name: String
        public var title: String
        public var description: String
        /// JSON Schema of the arguments object.
        public var inputSchema: JSONValue
        public var readOnly: Bool
        public var call: @Sendable (JSONValue) async -> ToolResult

        public init(name: String, title: String, description: String, inputSchema: JSONValue, readOnly: Bool,
                    call: @escaping @Sendable (JSONValue) async -> ToolResult) {
            self.name = name
            self.title = title
            self.description = description
            self.inputSchema = inputSchema
            self.readOnly = readOnly
            self.call = call
        }
    }

    public struct ToolResult: Sendable, Equatable {
        public var text: String
        public var structured: JSONValue?
        public var isError: Bool

        public init(text: String, structured: JSONValue? = nil, isError: Bool = false) {
            self.text = text
            self.structured = structured
            self.isError = isError
        }

        public static func error(_ text: String) -> ToolResult { ToolResult(text: text, isError: true) }
    }

    public struct Resource: Sendable {
        public var uri: String
        public var name: String
        public var description: String
        public var mimeType: String
        public var read: @Sendable () async -> String

        public init(uri: String, name: String, description: String, mimeType: String, read: @escaping @Sendable () async -> String) {
            self.uri = uri
            self.name = name
            self.description = description
            self.mimeType = mimeType
            self.read = read
        }
    }

    /// Newest first; a client asking for one of these gets it back, anything else gets the first.
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public var name: String
    public var version: String
    public var instructions: String
    public var tools: [Tool]
    public var resources: [Resource]
    /// Called with the client's `initialize` params (its `clientInfo` names the agent).
    public var onInitialize: (@Sendable (JSONValue) async -> Void)? = nil

    public init(name: String, version: String, instructions: String, tools: [Tool], resources: [Resource]) {
        self.name = name
        self.version = version
        self.instructions = instructions
        self.tools = tools
        self.resources = resources
    }

    /// One incoming line to at most one outgoing line; notifications get no reply.
    public func handle(line: String) async -> String? {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)), case .object = message else {
            return Self.encode(Self.failure(id: .null, code: -32700, message: "Parse error"))
        }
        guard let method = message["method"]?.string else {
            return Self.encode(Self.failure(id: message["id"] ?? .null, code: -32600, message: "Invalid request"))
        }
        guard let id = message["id"] else { return nil }
        return Self.encode(await respond(id: id, method: method, params: message["params"] ?? .object([:])))
    }

    func respond(id: JSONValue, method: String, params: JSONValue) async -> JSONValue {
        switch method {
        case "initialize":
            await onInitialize?(params)
            let asked = params["protocolVersion"]?.string ?? ""
            return Self.success(id: id, .object([
                "protocolVersion": .string(Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]),
                "capabilities": .object(["tools": .object([:]), "resources": .object([:])]),
                "serverInfo": .object(["name": .string(name), "version": .string(version)]),
                "instructions": .string(instructions),
            ]))
        case "ping":
            return Self.success(id: id, .object([:]))
        case "tools/list":
            return Self.success(id: id, .object(["tools": .array(tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "title": .string(tool.title),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                    // Writes go through macctl's journal or a checkpoint, so none is destructive.
                    "annotations": .object(["title": .string(tool.title), "readOnlyHint": .bool(tool.readOnly),
                                            "destructiveHint": .bool(false), "openWorldHint": .bool(false)]),
                ])
            })]))
        case "tools/call":
            guard let name = params["name"]?.string, let tool = tools.first(where: { $0.name == name }) else {
                return Self.failure(id: id, code: -32602, message: "Unknown tool: \(params["name"]?.string ?? "")")
            }
            let arguments = params["arguments"] ?? .object([:])
            guard case .object = arguments else { return Self.failure(id: id, code: -32602, message: "arguments must be an object") }
            let result = await tool.call(arguments)
            var body: [String: JSONValue] = [
                "content": .array([.object(["type": .string("text"), "text": .string(result.text)])]),
                "isError": .bool(result.isError),
            ]
            if let structured = result.structured { body["structuredContent"] = structured }
            return Self.success(id: id, .object(body))
        case "resources/list":
            return Self.success(id: id, .object(["resources": .array(resources.map { resource in
                .object(["uri": .string(resource.uri), "name": .string(resource.name),
                         "description": .string(resource.description), "mimeType": .string(resource.mimeType)])
            })]))
        case "resources/read":
            guard let uri = params["uri"]?.string, let resource = resources.first(where: { $0.uri == uri }) else {
                return Self.failure(id: id, code: -32002, message: "Resource not found: \(params["uri"]?.string ?? "")")
            }
            return Self.success(id: id, .object(["contents": .array([.object([
                "uri": .string(uri), "mimeType": .string(resource.mimeType), "text": .string(await resource.read()),
            ])])]))
        default:
            return Self.failure(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    static func success(id: JSONValue, _ result: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    static func failure(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .int(code), "message": .string(message)])])
    }

    /// Compact, one line: stdio framing is newline-delimited.
    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
    }
}
