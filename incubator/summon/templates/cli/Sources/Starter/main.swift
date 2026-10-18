import Foundation
import StarterCore

// Exit codes: 0 ok, 1 error, 2 usage.
do {
    let command = try Command.parse(Array(CommandLine.arguments.dropFirst()))
    print(command.output)
} catch {
    FileHandle.standardError.write(Data("\(Command.toolName): \(error)\n\n\(Command.usage)\n".utf8))
    exit(2)
}
