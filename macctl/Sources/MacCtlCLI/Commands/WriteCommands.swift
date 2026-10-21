import ArgumentParser
import Foundation
import MacCtlCore

/// Flags shared by commands that change settings.
struct ChangeOptions: ParsableArguments {
    @Flag(name: .long, help: "Show what would change; write nothing.")
    var dryRun = false

    @Flag(name: .shortAndLong, help: "Confirm admin or destructive settings.")
    var yes = false
}

struct SetCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "set",
            abstract: "Change one setting (a snapshot is saved first).",
            discussion: "Values are parsed for the setting's type: true/false, numbers, enum names, paths."
        )
    }

    @OptionGroup var global: GlobalOptions
    @OptionGroup var change: ChangeOptions

    @Argument(help: "Setting id, for example dock.autohide.")
    var id: String

    @Argument(help: "New value, for example true, 40, bottom, ~/Pictures/Screenshots.")
    var value: String

    func run() async throws {
        let (id, text, dryRun, yes) = (self.id, self.value, change.dryRun, change.yes)
        try await Output.run("set", global, text: Human.applied) {
            let service = makeService()
            let value = try service.parse(text, for: id)
            let profile = Profile(name: "set \(id)", settings: [id: value])
            return try await service.apply(profile, dryRun: dryRun, confirmed: yes)
        }
    }
}

struct DiffCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "diff",
            abstract: "Show what applying a profile would change. Writes nothing."
        )
    }

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Path to a profile JSON file.")
    var profile: String

    func run() async throws {
        let path = profile
        try await Output.run("diff", global, text: Self.render) {
            let profile = try ProfileLoader.load(path)
            let changes = try await makeService().diff(profile)
            return DiffResult(profile: profile.name, changes: changes)
        }
    }

    static func render(_ result: DiffResult) -> String {
        if result.changes.isEmpty { return "\(result.profile): no changes; this Mac already matches." }
        let n = result.changes.count
        return "\(result.profile): \(n) \(n == 1 ? "change" : "changes")\n" + Human.changes(result.changes)
    }
}

struct ApplyCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "apply",
            abstract: "Make this Mac match a profile. Idempotent; a snapshot is saved first."
        )
    }

    @OptionGroup var global: GlobalOptions
    @OptionGroup var change: ChangeOptions

    @Option(name: .long, help: "Only apply settings in this domain (dock, finder, ...).")
    var only: String?

    @Argument(help: "Path to a profile JSON file.")
    var profile: String

    func run() async throws {
        let (path, only, dryRun, yes) = (profile, self.only, change.dryRun, change.yes)
        try await Output.run("apply", global, text: Human.applied) {
            var profile = try ProfileLoader.load(path)
            if let only {
                profile.settings = profile.settings.filter { $0.key.hasPrefix(only + ".") }
                if profile.settings.isEmpty {
                    throw MacCtlError.invalidProfile("\(path) has no settings in domain \(only)")
                }
            }
            return try await makeService().apply(profile, dryRun: dryRun, confirmed: yes)
        }
    }
}

struct UndoCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "undo",
            abstract: "Roll back a change (the newest when no id is given).",
            discussion: """
            Keys changed by hand since macctl wrote them are left alone and reported (partial_restore).
            --force overwrites them too; it needs an explicit id.
            """
        )
    }

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Session id from `macctl snapshot list`.")
    var id: String?

    @Flag(name: .long, help: "Also restore keys changed by hand since macctl wrote them (needs an id).")
    var force = false

    func validate() throws {
        if force && id == nil { throw ValidationError("--force needs an explicit session id") }
    }

    func run() async throws {
        let id = self.id
        let force = self.force
        try await Output.run("undo", global, text: Human.restored) {
            try await makeService().undo(snapshotID: id, force: force)
        }
    }
}

struct RecoverCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "recover",
            abstract: "Roll back any macctl operation that was interrupted or failed.",
            discussion: """
            Reads the journal and puts every key an unfinished operation touched back to its prior state,
            newest first. Safe to run again: a second run changes nothing. Keys changed by hand are left
            alone and reported (partial_restore) unless --force.
            """
        )
    }

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Also restore keys changed by hand since macctl wrote them.")
    var force = false

    @Option(name: .long, help: "Set aside a corrupt journal (kept as <id>.jsonl.corrupt) so it stops blocking.")
    var abandon: String?

    func run() async throws {
        let force = self.force
        let abandon = self.abandon
        try await Output.run("recover", global, text: Human.recovered) {
            try await makeService().recover(force: force, abandon: abandon)
        }
    }
}
