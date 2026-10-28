import Foundation

/// One thing on this Mac with a newer version out: Summon itself, an agent CLI, a Homebrew formula or cask, a bun or
/// npm global package, or a macOS update. The panel's Update folder lists them by `Group`.
public struct SoftwareUpdate: Sendable, Equatable, Identifiable {
    public enum Source: String, Sendable, CaseIterable {
        case summon, agent, homebrew, bun, npm, macOS
    }

    /// The Update folder's sections, in order: Summon is a row of its own, the rest are folders.
    public enum Group: String, Sendable, CaseIterable {
        case summon, agents, homebrew, packages, os

        public var title: String {
            switch self {
            case .summon: return "Summon"
            case .agents: return "Agents"
            case .homebrew: return "Homebrew"
            case .packages: return "bun & npm"
            case .os: return "macOS"
            }
        }

        public var icon: String {
            switch self {
            case .summon: return "sparkles"
            case .agents: return "terminal"
            case .homebrew: return "shippingbox"
            case .packages: return "cube.box"
            case .os: return "apple.logo"
            }
        }
    }

    public var source: Source
    public var name: String
    public var current: String
    public var latest: String
    /// What installs it (absolute tool path first); nil when the app handles it (Summon, macOS's Software Update).
    public var command: [String]?

    public var id: String { "\(source.rawValue):\(name)" }
    public var title: String { current.isEmpty ? name : "\(name) \(current)" }

    public var group: Group {
        switch source {
        case .summon: return .summon
        case .agent: return .agents
        case .homebrew: return .homebrew
        case .bun, .npm: return .packages
        case .macOS: return .os
        }
    }

    public init(source: Source, name: String, current: String, latest: String, command: [String]?) {
        self.source = source
        self.name = name
        self.current = current
        self.latest = latest
        self.command = command
    }

    /// `brew outdated --json=v2`; pinned formulae stay put.
    public static func homebrew(_ json: String, brew: String) -> [SoftwareUpdate] {
        struct Outdated: Decodable {
            struct Package: Decodable {
                let name: String
                let installed_versions: [String]
                let current_version: String
                let pinned: Bool?
            }
            let formulae: [Package]
            let casks: [Package]
        }
        guard let outdated = try? JSONDecoder().decode(Outdated.self, from: jsonObject(json)) else { return [] }
        let formulae = outdated.formulae.filter { $0.pinned != true }.map {
            SoftwareUpdate(source: .homebrew, name: $0.name, current: $0.installed_versions.last ?? "",
                           latest: $0.current_version, command: [brew, "upgrade", $0.name])
        }
        let casks = outdated.casks.map {
            SoftwareUpdate(source: .homebrew, name: $0.name, current: $0.installed_versions.last ?? "",
                           latest: $0.current_version, command: [brew, "upgrade", "--cask", $0.name])
        }
        return formulae + casks
    }

    /// `bun outdated --global`: a table of `| Package | Current | Update | Latest |` rows.
    public static func bun(_ table: String, bun: String) -> [SoftwareUpdate] {
        let plain = table.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        return plain.split(whereSeparator: \.isNewline).compactMap { line in
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 4, cells[0] != "Package", !cells[0].hasPrefix("-"), cells[1] != cells[3] else { return nil }
            return SoftwareUpdate(source: .bun, name: cells[0], current: cells[1], latest: cells[3],
                                  command: [bun, "add", "-g", "\(cells[0])@latest"])
        }
    }

    /// `npm outdated -g --json`: `{"<package>": {"current", "latest", ...}}`.
    public static func npm(_ json: String, npm: String) -> [SoftwareUpdate] {
        struct Package: Decodable { let current: String?; let latest: String? }
        guard let packages = try? JSONDecoder().decode([String: Package].self, from: jsonObject(json)) else { return [] }
        return packages.sorted { $0.key < $1.key }.compactMap { name, package in
            guard let latest = package.latest, latest != package.current else { return nil }
            return SoftwareUpdate(source: .npm, name: name, current: package.current ?? "", latest: latest,
                                  command: [npm, "install", "-g", "\(name)@latest"])
        }
    }

    /// Agent CLIs (codex from bun, claude-code from Homebrew) get their own group, under the agent's name. The
    /// package's own upgrade command stays: an install is updated the way it was installed.
    public static func markAgents(_ updates: [SoftwareUpdate]) -> [SoftwareUpdate] {
        var agents: [String: String] = [:]
        for agent in AgentRegistry.all {
            if let package = AgentInstall.catalog[agent.id]?.npmPackage { agents[package] = agent.name }
            let hint = agent.installHint.split(separator: " ")
            if hint.starts(with: ["brew", "install"]), let formula = hint.last?.split(separator: "/").last {
                agents[String(formula)] = agent.name
            }
        }
        return updates.map { update in
            guard [.homebrew, .bun, .npm].contains(update.source), let name = agents[update.name] else { return update }
            var agent = update
            agent.source = .agent
            agent.name = name
            return agent
        }
    }

    /// The `{...}` in a tool's output: brew prints progress before it, npm prints notices after it.
    static func jsonObject(_ text: String) -> Data {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return Data() }
        return Data(text[start...end].utf8)
    }

    /// `softwareupdate -l`: a `Title: <name>, Version: <version>, ...` line under each `* Label:`.
    public static func macOS(_ text: String) -> [SoftwareUpdate] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.trimmingCharacters(in: .whitespaces).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            func value(_ key: String) -> String? {
                fields.first { $0.hasPrefix(key + ": ") }.map { String($0.dropFirst(key.count + 2)) }
            }
            guard let title = value("Title"), let version = value("Version") else { return nil }
            return SoftwareUpdate(source: .macOS, name: title, current: "", latest: version, command: nil)
        }
    }
}

/// Asks every package manager on this Mac what is outdated, all at once. A missing tool or a failed check adds
/// nothing: an update list is a hint, not an error.
public struct SoftwareUpdateCheck: Sendable {
    public let runner: Runner
    public let tools: ToolLocator

    public init(runner: @escaping Runner, tools: ToolLocator) {
        self.runner = runner
        self.tools = tools
    }

    public func run() async -> [SoftwareUpdate] {
        async let brew = check("brew", ["outdated", "--json=v2"]) { SoftwareUpdate.homebrew($0, brew: $1) }
        async let bun = check("bun", ["outdated", "--global"]) { SoftwareUpdate.bun($0, bun: $1) }
        async let npm = check("npm", ["outdated", "-g", "--json"]) { SoftwareUpdate.npm($0, npm: $1) }
        async let macOS = check("softwareupdate", ["-l"]) { text, _ in SoftwareUpdate.macOS(text) }
        return SoftwareUpdate.markAgents(await brew + bun + npm + macOS)
    }

    private func check(_ tool: String, _ arguments: [String],
                       parse: (String, String) -> [SoftwareUpdate]) async -> [SoftwareUpdate] {
        let path = tool == "softwareupdate" ? "/usr/sbin/softwareupdate" : tools.find(tool)
        guard let path else { return [] }
        do { return parse(try await runner(path, arguments), path) }
        // npm outdated exits 1 when something is outdated; its output is still the answer.
        catch RunnerError.failed(_, _, let output) { return parse(output, path) }
        catch { return [] }
    }
}

extension MenuTree {
    /// Fills the panel's Update folder (`update`, the default menu's group; added after Make Something when a
    /// custom menu has none): Summon as a row, a folder per other group, Update All and Check Now. An update row is
    /// `<folder>.<n>`, where n indexes `updates`; its tag is the new version.
    public func withUpdates(_ updates: [SoftwareUpdate]) -> MenuTree {
        guard !items.contains(where: { $0.id == "update.check" }) else { return self }
        var updated = items
        var rows: [MenuItem] = []
        let tag = updates.isEmpty ? nil : "\(updates.count) new"
        let insertAt: Int
        if let index = updated.firstIndex(where: { $0.id == "update" }) {
            updated[index].badge = tag
            insertAt = index + 1
        } else {
            rows.append(MenuItem(id: "update", label: "Update", icon: "arrow.triangle.2.circlepath", aliases: ["upgrade"], badge: tag))
            insertAt = (items.lastIndex { $0.id == "make" || $0.id.hasPrefix("make.") }).map { $0 + 1 } ?? items.endIndex
        }
        for group in SoftwareUpdate.Group.allCases {
            let members = updates.enumerated().filter { $0.element.group == group }
            guard !members.isEmpty else { continue }
            let folder = group == .summon ? "update" : "update.\(group.rawValue)"
            if group != .summon {
                rows.append(MenuItem(id: folder, label: group.title, icon: group.icon, badge: "\(members.count)"))
                // Only this tool's own upgrade commands, no agent (owner, 2026-10-28).
                if members.filter({ $0.element.command != nil }).count > 1 {
                    rows.append(MenuItem(id: "\(folder).all", label: "Update All \(group.title)", icon: "arrow.down.circle"))
                }
            }
            for (index, update) in members {
                rows.append(MenuItem(id: "\(folder).\(index)", label: update.title, icon: group.icon, badge: "New \(update.latest)"))
            }
        }
        if updates.filter({ $0.command != nil }).count > 1 {
            rows.append(MenuItem(id: "update.all", label: "Update All", icon: "arrow.down.circle"))
        }
        if updates.isEmpty { rows.append(MenuItem(id: "update.none", label: "Everything is up to date", icon: "checkmark.circle")) }
        rows.append(MenuItem(id: "update.check", label: "Check Now", icon: "arrow.clockwise"))
        updated.insert(contentsOf: rows, at: insertAt)
        return (try? MenuTree(items: updated)) ?? self
    }

    /// Update rows have no shell action: the app installs them (`SummonModel.runUpdate`).
    public static func runsInApp(_ id: String) -> Bool {
        id == "update.check" || (id.hasPrefix("update.") && id.hasSuffix(".all")) || updateIndex(id) != nil
    }

    /// The index into `updates` for an update row, nil for every other item (`update.brew` from a menu file too).
    public static func updateIndex(_ id: String) -> Int? {
        guard id.hasPrefix("update."), let last = id.split(separator: ".").last else { return nil }
        return Int(last)
    }
}
