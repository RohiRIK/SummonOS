import Foundation

/// One entry of the Summon Menu, as written in `menu.jsonc`. Dotted ids define the tree:
/// `style.theme` is a child of `style`. The file is an array so the order you write is the order you see.
public struct MenuItem: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var label: String
    /// SF Symbol name.
    public var icon: String?
    /// Shell command run with the user's login shell when chosen. Items without one only open their children.
    public var action: String?
    /// Shell guard: the item is shown only when this exits 0.
    public var when: String?
    /// Shell guard: a check mark is shown when this exits 0.
    public var checked: String?
    public var aliases: [String]?

    public init(id: String, label: String, icon: String? = nil, action: String? = nil,
                when: String? = nil, checked: String? = nil, aliases: [String]? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.action = action
        self.when = when
        self.checked = checked
        self.aliases = aliases
    }

    public var parentID: String? {
        guard let dot = id.lastIndex(of: ".") else { return nil }
        return String(id[..<dot])
    }
}

public struct MenuFile: Sendable, Equatable, Codable {
    public var items: [MenuItem]

    public init(items: [MenuItem]) {
        self.items = items
    }
}

public struct MenuTree: Sendable, Equatable {
    public let items: [MenuItem]

    public enum LoadError: Error, Equatable, Sendable {
        case duplicateID(String)
        case missingParent(String)
    }

    public init(items: [MenuItem]) throws {
        var seen = Set<String>()
        for item in items {
            guard seen.insert(item.id).inserted else { throw LoadError.duplicateID(item.id) }
        }
        for item in items {
            if let parent = item.parentID, !seen.contains(parent) {
                throw LoadError.missingParent(item.id)
            }
        }
        self.items = items
    }

    public static func parse(_ jsonc: String) throws -> MenuTree {
        let json = JSONC.stripComments(jsonc)
        let file = try JSONDecoder().decode(MenuFile.self, from: Data(json.utf8))
        return try MenuTree(items: file.items)
    }

    public static var standard: MenuTree {
        // The bundled menu is covered by a test, so this cannot fail at runtime.
        (try? parse(DefaultMenu.jsonc)) ?? (try! MenuTree(items: []))
    }

    public func item(_ id: String) -> MenuItem? {
        items.first { $0.id == id }
    }

    /// Direct children of `parent`, or the top level when `parent` is nil, in file order.
    public func children(of parent: String?) -> [MenuItem] {
        items.filter { $0.parentID == parent }
    }

    /// Returns a new menu tree with registered projects included under a "My Apps" submenu.
    public func withProjects(_ projects: [Project]) -> MenuTree {
        guard !projects.isEmpty, !items.contains(where: { $0.id == "apps" }) else { return self }
        var updated = items
        let appsParent = MenuItem(id: "apps", label: "My Apps", icon: "square.grid.2x2", aliases: ["apps"])
        if let agentIndex = updated.firstIndex(where: { $0.id == "agent" }) {
            let lastAgentChildIndex = updated.lastIndex(where: { $0.id.hasPrefix("agent.") }) ?? agentIndex
            updated.insert(appsParent, at: lastAgentChildIndex + 1)
            for (offset, project) in projects.enumerated() {
                updated.insert(MenuItem(
                    id: "apps.\(project.name)",
                    label: project.name,
                    icon: project.kind.systemImage,
                    action: "summon project open \(project.name)"
                ), at: lastAgentChildIndex + 2 + offset)
            }
        } else {
            updated.append(appsParent)
            for project in projects {
                updated.append(MenuItem(
                    id: "apps.\(project.name)",
                    label: project.name,
                    icon: project.kind.systemImage,
                    action: "summon project open \(project.name)"
                ))
            }
        }
        return (try? MenuTree(items: updated)) ?? self
    }

    /// Items with an action whose label, alias or id contains every word of `query`, in file order.
    public func search(_ query: String) -> [MenuItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return items.filter { item in
            guard item.action != nil else { return false }
            let haystack = ([item.label, item.id] + (item.aliases ?? [])).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// The labels from the top level down to `id`, for breadcrumbs in search results.
    public func path(to id: String) -> [String] {
        var labels: [String] = []
        var current: String? = id
        while let currentID = current, let found = self.item(currentID) {
            labels.insert(found.label, at: 0)
            current = found.parentID
        }
        return labels
    }
}

public enum JSONC {
    /// Removes `//` line comments and `/* */` block comments outside strings, and trailing commas before `]` or `}`.
    public static func stripComments(_ text: String) -> String {
        var output = ""
        var inString = false
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            let next = text.index(after: index)
            let nextChar: Character? = next < text.endIndex ? text[next] : nil
            if inString {
                output.append(char)
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                index = next
                continue
            }
            if char == "\"" {
                inString = true
                output.append(char)
                index = next
            } else if char == "/" && nextChar == "/" {
                while index < text.endIndex && text[index] != "\n" {
                    index = text.index(after: index)
                }
            } else if char == "/" && nextChar == "*" {
                index = text.index(after: next)
                while index < text.endIndex {
                    let after = text.index(after: index)
                    if text[index] == "*" && after < text.endIndex && text[after] == "/" {
                        index = text.index(after: after)
                        break
                    }
                    index = after
                }
            } else {
                output.append(char)
                index = next
            }
        }
        return removeTrailingCommas(output)
    }

    private static func removeTrailingCommas(_ text: String) -> String {
        var output = ""
        var inString = false
        var escaped = false
        var pendingComma = false
        var pendingWhitespace = ""
        for char in text {
            if inString {
                output.append(char)
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { inString = false }
                continue
            }
            if pendingComma {
                if char.isWhitespace {
                    pendingWhitespace.append(char)
                    continue
                }
                if char != "]" && char != "}" {
                    output.append(",")
                }
                output.append(pendingWhitespace)
                pendingComma = false
                pendingWhitespace = ""
            }
            if char == "," {
                pendingComma = true
                continue
            }
            if char == "\"" { inString = true }
            output.append(char)
        }
        if pendingComma { output.append(",") }
        output.append(pendingWhitespace)
        return output
    }
}

extension MenuTree {
    /// The user's menu file when it exists and parses; otherwise the bundled default, with the reason
    /// it was not used. One rule for the app and the CLI.
    public static func load(from url: URL) -> (tree: MenuTree, problem: String?) {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return (.standard, nil)
        }
        do {
            return (try MenuTree.parse(String(decoding: data, as: UTF8.self)), nil)
        } catch {
            return (.standard, "\(url.lastPathComponent) could not be read (\(error)); using the default menu.")
        }
    }
}
