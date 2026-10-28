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
    /// Release notes or the package page ("What's New").
    public var link: String?

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

    public init(source: Source, name: String, current: String, latest: String, command: [String]?, link: String? = nil) {
        self.source = source
        self.name = name
        self.current = current
        self.latest = latest
        self.command = command
        self.link = link
    }

    /// What Siri says for "What needs updating?": the count and up to three names.
    public static func spoken(_ updates: [SoftwareUpdate]) -> String {
        guard !updates.isEmpty else { return "Everything is up to date." }
        let names = updates.prefix(3).map(\.name)
        let more = updates.count > 3 ? " and \(updates.count - 3) more" : ""
        let count = updates.count == 1 ? "1 update" : "\(updates.count) updates"
        return "\(count): " + names.joined(separator: ", ") + more + "."
    }

    /// Fix with AI on a failed row: the command, the end of its output, and a narrow brief.
    public func fixPrompt(output: String) -> String {
        let shown = command.map { $0.joined(separator: " ") } ?? name
        let tail = String(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(4000))
        return """
        Updating \(name) (\(group.title)) from \(current.isEmpty ? "?" : current) to \(latest) failed.
        Command: \(shown)
        Output (end):
        \(tail)

        Find why it failed, fix the cause, and run the update again. Touch only what this update needs.
        If it needs my password (sudo), tell me the exact command to run instead.
        """
    }

    /// Summon's own row: the release page is its "What's New".
    public static func summon(current: String, latest: String, tag: String) -> SoftwareUpdate {
        SoftwareUpdate(source: .summon, name: "Summon", current: current, latest: latest, command: nil,
                       link: "https://github.com/RohiRIK/SummonOS/releases/tag/\(tag)")
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
                           latest: $0.current_version, command: [brew, "upgrade", $0.name],
                           link: "https://formulae.brew.sh/formula/\($0.name)")
        }
        let casks = outdated.casks.map {
            SoftwareUpdate(source: .homebrew, name: $0.name, current: $0.installed_versions.last ?? "",
                           latest: $0.current_version, command: [brew, "upgrade", "--cask", $0.name],
                           link: "https://formulae.brew.sh/cask/\($0.name)")
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
                                  command: [bun, "add", "-g", "\(cells[0])@latest"],
                                  link: "https://www.npmjs.com/package/\(cells[0])")
        }
    }

    /// `npm outdated -g --json`: `{"<package>": {"current", "latest", ...}}`.
    public static func npm(_ json: String, npm: String) -> [SoftwareUpdate] {
        struct Package: Decodable { let current: String?; let latest: String? }
        guard let packages = try? JSONDecoder().decode([String: Package].self, from: jsonObject(json)) else { return [] }
        return packages.sorted { $0.key < $1.key }.compactMap { name, package in
            guard let latest = package.latest, latest != package.current else { return nil }
            return SoftwareUpdate(source: .npm, name: name, current: package.current ?? "", latest: latest,
                                  command: [npm, "install", "-g", "\(name)@latest"],
                                  link: "https://www.npmjs.com/package/\(name)")
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

/// What an update row is doing in the Updates window.
public enum UpdateRowState: Sendable, Equatable {
    /// Waiting for the update before it: package managers take a lock, so installs run one at a time.
    case queued
    case running
    case done
    /// The command's output, for Show Details.
    case failed(String)

    /// A failure that wants a password (a cask's installer runs sudo): offer Open in Terminal.
    public var needsTerminal: Bool {
        guard case .failed(let output) = self else { return false }
        let text = output.lowercased()
        return text.contains("sudo") || text.contains("password") || text.contains("a terminal is required")
    }
}

/// The Updates window's choices: `~/.config/summon/update-preferences.json`.
public struct UpdatePreferences: Codable, Sendable, Equatable {
    /// Groups the check leaves out (Settings › Updates).
    public var off: Set<String> = []
    /// Install agent updates as soon as a check finds them.
    public var autoUpdateAgents = false
    /// Skip This Version: update id → the version skipped. A newer version shows again.
    public var skipped: [String: String] = [:]

    public init() {}

    public func includes(_ group: SoftwareUpdate.Group) -> Bool { !off.contains(group.rawValue) }

    /// What the window and the panel count: checked groups, minus skipped versions.
    public func shown(_ updates: [SoftwareUpdate]) -> [SoftwareUpdate] {
        updates.filter { includes($0.group) && skipped[$0.id] != $0.latest }
    }
}

public struct UpdatePreferencesStore: Sendable {
    public let paths: SummonPaths
    public init(paths: SummonPaths) { self.paths = paths }
    public var file: URL { paths.config.appendingPathComponent("update-preferences.json") }

    public func load() -> UpdatePreferences {
        (try? JSONDecoder().decode(UpdatePreferences.self, from: Data(contentsOf: file))) ?? UpdatePreferences()
    }

    public func save(_ preferences: UpdatePreferences) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try TextFile.write(String(decoding: try encoder.encode(preferences), as: UTF8.self) + "\n", to: file)
    }
}

extension MenuTree {
    /// The panel's Update row (`update`, the default menu's group; added after Make Something when a custom menu has
    /// none), tagged "N new". Choosing it opens the Updates window, which lists them.
    public func withUpdates(count: Int) -> MenuTree {
        let tag = count == 0 ? nil : "\(count) new"
        var updated = items
        if let index = updated.firstIndex(where: { $0.id == "update" }) {
            updated[index].badge = tag
        } else {
            let row = MenuItem(id: "update", label: "Update", icon: "arrow.triangle.2.circlepath", aliases: ["upgrade"], badge: tag)
            let afterMake = (items.lastIndex { $0.id == "make" || $0.id.hasPrefix("make.") }).map { $0 + 1 } ?? items.endIndex
            updated.insert(row, at: afterMake)
        }
        return (try? MenuTree(items: updated)) ?? self
    }

    /// `update` opens the Updates window instead of running a shell action or drilling into its children.
    public static func runsInApp(_ id: String) -> Bool { id == "update" }
}
