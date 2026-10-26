import Foundation

/// One thing on this Mac with a newer version out: Summon itself, a Homebrew formula or cask, a bun or npm global
/// package, or a macOS update. The panel's Updates folder lists them.
public struct SoftwareUpdate: Sendable, Equatable, Identifiable {
    public enum Source: String, Sendable, CaseIterable {
        case summon, homebrew, bun, npm, macOS

        public var icon: String {
            switch self {
            case .summon: return "sparkles"
            case .homebrew: return "shippingbox"
            case .bun, .npm: return "cube.box"
            case .macOS: return "apple.logo"
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
    public var title: String { current.isEmpty ? "\(name) \(latest)" : "\(name) \(current) → \(latest)" }

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
        return await brew + bun + npm + macOS
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
    /// The panel's Updates folder, right after Make Something: one row per update (`updates.<n>`, in `updates`
    /// order), Update All when more than one installs from the shell, and Check Now.
    public func withUpdates(_ updates: [SoftwareUpdate]) -> MenuTree {
        guard !items.contains(where: { $0.id == "updates" }) else { return self }
        var rows = [MenuItem(id: "updates", label: updates.isEmpty ? "Updates" : "Updates · \(updates.count)",
                             icon: "arrow.down.circle", aliases: ["upgrade", "outdated", "brew", "bun", "npm"])]
        if updates.filter({ $0.command != nil }).count > 1 {
            rows.append(MenuItem(id: "updates.all", label: "Update All", icon: "arrow.down.circle.fill"))
        }
        for (index, update) in updates.enumerated() {
            rows.append(MenuItem(id: "updates.\(index)", label: update.title, icon: update.source.icon))
        }
        if updates.isEmpty { rows.append(MenuItem(id: "updates.none", label: "Everything is up to date", icon: "checkmark.circle")) }
        rows.append(MenuItem(id: "updates.check", label: "Check Now", icon: "arrow.clockwise"))
        var updated = items
        let afterMake = (items.lastIndex { $0.id == "make" || $0.id.hasPrefix("make.") }).map { $0 + 1 } ?? items.endIndex
        updated.insert(contentsOf: rows, at: afterMake)
        return (try? MenuTree(items: updated)) ?? self
    }
}
