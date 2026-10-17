import AppKit
import Foundation
import SummonCore

enum IconCommands {
    /// `summon icon set <image> <path>` and `summon icon reset <path>`: a custom Finder icon on any file, folder or app.
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) throws {
        switch args.next() {
        case "set":
            guard let imageArg = args.next(), let targetArg = args.next() else {
                throw CLIError("Usage: summon icon set <image> <path>")
            }
            let imagePath = (imageArg as NSString).expandingTildeInPath
            let target = (targetArg as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: target) else { throw CLIError("No such file or folder: \(target)") }
            guard let image = NSImage(contentsOfFile: imagePath) else { throw CLIError("Not an image macOS can read: \(imagePath)") }
            guard NSWorkspace.shared.setIcon(image, forFile: target, options: []) else {
                throw CLIError("macOS refused to set the icon on \(target). Apps in /Applications may need admin rights, and app updates reset custom icons.")
            }
            print("Icon set on \(target)")
        case "reset":
            guard let targetArg = args.next() else { throw CLIError("Usage: summon icon reset <path>") }
            let target = (targetArg as NSString).expandingTildeInPath
            guard NSWorkspace.shared.setIcon(nil, forFile: target, options: []) else {
                throw CLIError("macOS refused to reset the icon on \(target).")
            }
            print("Icon reset on \(target)")
        default:
            throw CLIError("Usage: summon icon set <image> <path> | reset <path>")
        }
    }
}

enum PathCommand {
    /// Where Summon's shared files live (themes, skills, wallpapers): `$SUMMON_PATH`, else `<binary>/../share/summon`,
    /// else the folder holding the binary. Printed by `summon path` so skills never hard-code it.
    static func installPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let explicit = environment["SUMMON_PATH"], !explicit.isEmpty {
            return (explicit as NSString).expandingTildeInPath
        }
        // argv[0] is only the name typed when run from PATH, so ask the loader for the real path.
        let binary = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        let binDir = binary.deletingLastPathComponent()
        let share = binDir.deletingLastPathComponent().appendingPathComponent("share/summon", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: share.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return share.path
        }
        return binDir.path
    }
}
