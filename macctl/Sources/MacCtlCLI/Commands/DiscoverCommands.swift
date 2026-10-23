import ArgumentParser
import Foundation
import MacCtlCore

struct DiscoverCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "discover",
            abstract: "Find the preference key behind a System Settings control. Read-only.",
            discussion: """
            1. macctl discover start      (saves every key of the watched domains)
            2. change one control in System Settings
            3. macctl discover diff       (lists the keys that changed, with a draft catalog entry)
            Nothing is written to preferences. The baseline is private (0600) and diff prints only changed keys.
            """,
            subcommands: [DiscoverStartCommand.self, DiscoverDiffCommand.self]
        )
    }
}

struct DiscoverStartCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "start", abstract: "Save a baseline of the watched preference domains.")
    }

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "A domain to watch (repeatable), for example com.apple.dock. Default: the usual System Settings domains.")
    var domain: [String] = []

    func run() async throws {
        let domains = domain.isEmpty ? Discovery.defaultDomains : domain
        try await Output.run("discover start", global, text: Self.render) {
            let (preferences, store) = makeDiscovery()
            let baseline = Discovery.capture(preferences, domains: domains, macOSVersion: macOSProductVersion())
            try store.save(baseline)
            return DiscoverStarted(baseline: store.file.path, domains: domains,
                                   keys: baseline.domains.reduce(0) { $0 + $1.values.count })
        }
    }

    static func render(_ result: DiscoverStarted) -> String {
        "Saved \(result.keys) keys from \(result.domains.count) domains.\n"
            + "Now change one control in System Settings, then run: macctl discover diff"
    }
}

struct DiscoverDiffCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "diff", abstract: "List the keys that changed since `discover start`.")
    }

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Output.run("discover diff", global, text: Self.render) {
            let (preferences, store) = makeDiscovery()
            let baseline = try store.load()
            let domains = baseline.domains.map(\.appID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let current = Discovery.capture(preferences, domains: domains, macOSVersion: macOSProductVersion())
            return Discovery.diff(baseline, current)
        }
    }

    static func render(_ report: Discovery.Report) -> String {
        if report.changes.isEmpty {
            return "No keys changed in \(report.domains.count) domains. Some controls write elsewhere: "
                + "try `macctl discover start --domain <domain>` with the app's own domain."
        }
        var lines = ["\(report.changes.count) \(report.changes.count == 1 ? "key" : "keys") changed:"]
        lines.append(Human.table(report.changes.map { change in
            let domain = change.host == .currentHost ? "\(change.appID) (currentHost)" : change.appID
            return ["  " + domain, change.key, change.before.map(\.description) ?? "(unset)", "->",
                    change.after.map(\.description) ?? "(unset)"]
        }))
        let drafts = report.changes.compactMap(\.suggestion)
        if !drafts.isEmpty {
            lines.append("Draft catalog entries (check the meaning, range and default on a Mac before adding):")
            lines += drafts.map { "  " + $0 }
        }
        return lines.joined(separator: "\n")
    }
}

struct DiscoverStarted: Encodable {
    let baseline: String
    let domains: [String]
    let keys: Int
}
