import Foundation
import MacAssistantCore

// Command-line entry point. It shares the coordinator, policy broker, and tools with the app, so
// switching clients never changes what an operation may do. Commands arrive with the workflow (M1).

let arguments = CommandLine.arguments.dropFirst()

switch arguments.first {
case "--version", "version":
    print("mac-assistant \(MacAssistant.version)")
default:
    print("""
    usage: mac-assistant <command>

      version    print the version
    """)
}
