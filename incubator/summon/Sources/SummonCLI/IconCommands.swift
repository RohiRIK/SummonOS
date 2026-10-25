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

enum SkillCommands {
    static var source: URL {
        URL(fileURLWithPath: PathCommand.installPath()).appendingPathComponent("skills", isDirectory: true)
    }

    /// `summon skills` lists the shipped skill files; `summon skills link` links them into every agent's folder.
    static func run(_ args: inout Arguments, _ context: Context) throws {
        switch args.next() {
        case nil, "list":
            if args.flag("--json") {
                let infos = SkillLinker.skillNames(in: source).map { name in
                    SkillInfo(name: name, description: (try? String(contentsOf: source.appendingPathComponent("\(name)/SKILL.md"), encoding: .utf8))
                        .flatMap(SkillInfo.description(fromSkillFile:)))
                }
                try context.printJSON(infos)
            } else {
                SkillLinker.skillFiles(in: source).forEach { print($0) }
            }
        case "link":
            let quiet = args.flag("--quiet")
            let settings = try AgentSettingsStore(paths: context.paths).loadValidated()
            let result = try SkillLinker(home: context.paths.home).link(from: source, settings: settings) { agent in
                context.tools.find(agent.command) != nil
            }
            for path in result.kept {
                context.warn("Leaving your own \(path) in place")
            }
            if !quiet {
                print(result.folders.isEmpty ? "No agent is installed, so no skills were linked." :
                      "Linked \(SkillLinker.skillNames(in: source).joined(separator: ", ")) into " +
                      result.folders.map { "~/" + $0 }.joined(separator: ", "))
            }
        default:
            throw CLIError("Usage: summon skills [list] | summon skills link [--quiet]")
        }
    }

    /// The SKILL.md files chosen for this agent, listed in every prompt's session brief: agents without a skill
    /// mechanism read the files directly.
    static func skillFiles(agent: String, settings: AgentSettings) -> [String] {
        settings.skills(for: agent, shipped: SkillLinker.skillNames(in: source))
            .map { source.appendingPathComponent("\($0)/SKILL.md").path }
    }
}

enum PathCommand {
    /// Where Summon's shared files live (themes, skills, wallpapers): `$SUMMON_PATH`, else `<binary>/../share/summon`,
    /// else the folder holding the binary. Printed by `summon path` so skills never hard-code it.
    static func installPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        SummonPaths.installPath(environment: environment)
    }
}
