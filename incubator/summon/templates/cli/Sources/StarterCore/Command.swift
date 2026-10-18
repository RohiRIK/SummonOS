/// What the user asked for, parsed from argv. Replace `greet` with your tool's real commands;
/// keep parsing and the work here, Foundation only, tested in StarterCoreTests.
public enum Command: Equatable, Sendable {
    case help
    case version
    case greet(name: String, loud: Bool)

    public static let toolName = "cli-starter"
    public static let version = "0.1.0"

    public static let usage = """
    usage: \(toolName) [--loud] [name]
           \(toolName) --help | --version

    Greets name (default: world). --loud shouts it.
    """

    public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        case unknownOption(String)
        case tooManyArguments([String])

        public var description: String {
            switch self {
            case let .unknownOption(option): "unknown option \(option)"
            case let .tooManyArguments(extra): "unexpected arguments: \(extra.joined(separator: " "))"
            }
        }
    }

    /// `arguments` excludes the program name.
    public static func parse(_ arguments: [String]) throws(ParseError) -> Command {
        var loud = false
        var names: [String] = []
        for argument in arguments {
            switch argument {
            case "-h", "--help": return .help
            case "--version": return .version
            case "--loud": loud = true
            case let option where option.hasPrefix("-"): throw .unknownOption(option)
            default: names.append(argument)
            }
        }
        guard names.count <= 1 else { throw .tooManyArguments(Array(names.dropFirst())) }
        return .greet(name: names.first ?? "world", loud: loud)
    }

    /// The text to print for a parsed command.
    public var output: String {
        switch self {
        case .help: Self.usage
        case .version: "\(Self.toolName) \(Self.version)"
        case let .greet(name, loud):
            loud ? "HELLO, \(name.uppercased())!" : "Hello, \(name)."
        }
    }
}
