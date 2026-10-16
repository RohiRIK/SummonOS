import ArgumentParser
import Foundation
import MacCtlCore

struct SnapshotCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "snapshot",
            abstract: "Inspect the snapshots saved before each change.",
            subcommands: [SnapshotListCommand.self, SnapshotShowCommand.self],
            defaultSubcommand: SnapshotListCommand.self
        )
    }
}

struct SnapshotListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "list", abstract: "List snapshots, newest first.")
    }

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Output.run("snapshot list", global, text: Self.render) {
            try makeService().snapshots().map(SnapshotSummary.init)
        }
    }

    static func render(_ snapshots: [SnapshotSummary]) -> String {
        if snapshots.isEmpty { return "No snapshots yet." }
        let rows = snapshots.map { snap in
            [snap.id, snap.createdAt.formatted(date: .abbreviated, time: .standard),
             "\(snap.changeCount)", snap.settings.joined(separator: ", ")]
        }
        return Human.table([["ID", "CREATED", "CHANGES", "SETTINGS"]] + rows)
    }
}

struct SnapshotShowCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "show", abstract: "Show the old values a snapshot holds.")
    }

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Snapshot id from `macctl snapshot list`.")
    var id: String

    func run() async throws {
        let id = self.id
        try await Output.run("snapshot show", global, text: Self.render) {
            guard let snapshot = try makeService().snapshots().first(where: { $0.id == id }) else {
                throw MacCtlError.snapshotNotFound(id)
            }
            return snapshot
        }
    }

    /// A snapshot's `from` is the value undo restores; `to` is what the apply wrote.
    static func render(_ snapshot: Snapshot) -> String {
        let header = "Snapshot \(snapshot.id), \(snapshot.createdAt.formatted(date: .abbreviated, time: .standard))"
        if snapshot.changes.isEmpty { return header + "\n  (no changes)" }
        let rows = snapshot.changes.map { ["  " + $0.id, Human.value($0.from), "(was)", Human.value($0.to), "(set)"] }
        return header + "\n" + Human.table(rows)
    }
}
