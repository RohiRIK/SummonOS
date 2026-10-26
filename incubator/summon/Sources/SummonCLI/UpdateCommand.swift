import Foundation
import SummonCore

enum UpdateCommand {
    static let usage = "Usage: summon update [--channel stable|edge] [--check] [--yes]"

    /// `summon update`: check the channel, download and verify the build, install it with rollback, then run doctor.
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        let checkOnly = args.flag("--check")
        let yes = args.flag("--yes") || args.flag("-y")
        let named = args.option("--channel")
        guard args.isEmpty else { throw CLIError(usage) }
        let store = UpdateChannelStore(paths: context.paths)
        var channel = store.load()
        if let named {
            guard let chosen = UpdateChannel(rawValue: named) else { throw CLIError("Unknown channel: \(named)\n\(usage)") }
            channel = chosen
            // An explicit channel is remembered, so `summon update` alone keeps following it (not for a mere --check).
            if !checkOnly { try store.save(chosen) }
        }

        // Downloads can outlast the default 60-second deadline on a slow connection.
        let updater = Updater(runner: Shell.live(timeout: 900), gh: context.tools.find("gh"))
        let check = try await updater.check(channel)
        print("Installed: summon \(check.current)")
        print("Latest on \(channel.rawValue): \(check.release.version) (release \(check.release.tag))")
        guard check.available else {
            print("Summon is up to date.")
            return
        }
        if checkOnly {
            print("An update is available. Install it with: summon update\(named == nil ? "" : " --channel \(channel.rawValue)")")
            return
        }
        if !yes {
            guard isatty(STDIN_FILENO) == 1 else { throw CLIError("Run summon update --yes to install \(check.release.version) without a prompt.") }
            print("Install SummonOS \(check.release.version)? [y/N] ", terminator: "")
            guard let answer = readLine(), answer.lowercased().hasPrefix("y") else {
                print("Nothing was changed.")
                return
            }
        }

        print("Downloading \(check.release.zipName)")
        let output = try await updater.install(check.release)
        print(output.trimmingCharacters(in: .whitespacesAndNewlines))

        // The new binary checks its own install; this process is still the old one.
        print("Checking the install")
        let doctor = Process()
        doctor.executableURL = context.paths.home.appendingPathComponent(".local/bin/summon")
        doctor.arguments = ["doctor"]
        try doctor.run()
        doctor.waitUntilExit()
        guard doctor.terminationStatus == 0 else {
            throw CLIError("SummonOS \(check.release.version) was installed, but summon doctor found failed checks. Review the output and run summon doctor again after resolving them.")
        }
        print("SummonOS \(check.release.version) is installed. Restart Summon.app to use the new menu app.")
    }
}
