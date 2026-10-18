import ArgumentParser
import Foundation
import MacCtlCore

struct DoctorCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "doctor",
            abstract: "Show the macOS version, which permissions are granted, and how to fix what is missing."
        )
    }

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Output.run("doctor", global, text: Self.render) {
            await makeService().doctor()
        }
    }

    static func render(_ report: DoctorReport) -> String {
        var rows: [[String]] = []
        for check in report.checks {
            rows.append([check.ok ? "ok" : "MISSING", check.name, check.detail])
            if !check.ok, let url = check.fixURL {
                rows.append(["", "", "fix: \(url)"])
            }
        }
        let table = Human.table(rows)
        return table.isEmpty ? "macOS \(report.macOSVersion)" : "macOS \(report.macOSVersion)\n\(table)"
    }
}

struct ListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "List every setting macctl knows, with its type, risk and current value."
        )
    }

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Only settings in this domain (dock, finder, keyboard, ...).")
    var domain: String?

    func run() async throws {
        let domain = self.domain
        try await Output.run("list", global, text: Self.render) {
            let service = makeService()
            var settings = service.settings
            if let domain {
                settings = settings.filter { $0.domain == domain }
                if settings.isEmpty {
                    throw MacCtlError.unknownSetting("domain \(domain)")
                }
            }
            var infos: [SettingInfo] = []
            for setting in settings {
                infos.append(await SettingInfo.load(setting, from: service))
            }
            return infos
        }
    }

    static func render(_ infos: [SettingInfo]) -> String {
        let header = ["ID", "TYPE", "RISK", "CURRENT"]
        let rows = infos.map { info in
            [info.id, info.type.text, info.risk.rawValue, info.currentError == nil ? Human.value(info.current) : "(error)"]
        }
        return Human.table([header] + rows)
    }
}

struct DescribeCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "describe",
            abstract: "Full schema of one setting: type, allowed values, risk, permissions, side effects."
        )
    }

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Setting id, for example dock.autohide.")
    var id: String

    func run() async throws {
        let id = self.id
        try await Output.run("describe", global, text: Self.render) {
            let service = makeService()
            let setting = try service.setting(id)
            return await SettingInfo.load(setting, from: service)
        }
    }

    static func render(_ info: SettingInfo) -> String {
        var rows: [[String]] = [
            ["id", info.id],
            ["summary", info.summary],
            ["type", info.type.text],
            ["risk", info.risk.rawValue],
            ["current", Human.value(info.current)],
            ["default", Human.value(info.systemDefault)],
            ["backend", info.backend],
            ["permissions", info.permissions.isEmpty ? "none" : info.permissions.joined(separator: ", ")],
            ["after", info.sideEffects.isEmpty ? "none" : info.sideEffects.joined(separator: ", ")],
            ["verified", info.verified ? "macOS " + info.verifiedOn.joined(separator: ", ") : "no"],
        ]
        if let error = info.currentError {
            rows.append(["error", error])
        }
        return Human.table(rows.map { [$0[0] + ":", $0[1]] })
    }
}

struct GetCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "get",
            abstract: "Print the current value of one or more settings."
        )
    }

    @OptionGroup var global: GlobalOptions

    @Argument(help: "One or more setting ids.")
    var ids: [String] = []

    func validate() throws {
        if ids.isEmpty {
            throw ValidationError("Give at least one setting id, for example: macctl get dock.autohide")
        }
    }

    func run() async throws {
        let ids = self.ids
        try await Output.run("get", global, text: Self.render) {
            let service = makeService()
            var values: [SettingValue] = []
            for id in ids {
                values.append(SettingValue(id: id, value: try await service.get(id)))
            }
            return values
        }
    }

    static func render(_ values: [SettingValue]) -> String {
        if values.count == 1 { return Human.value(values[0].value) }
        return Human.table(values.map { [$0.id, Human.value($0.value)] })
    }
}
