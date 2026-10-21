import Foundation
import Testing
@testable import SummonCore

@Suite("Summon Menu")
struct MenuTests {
    @Test func defaultMenuParses() throws {
        let tree = try MenuTree.parse(DefaultMenu.jsonc)
        #expect(tree.items.count > 30)
        #expect(tree.children(of: nil).map(\.id) == ["agent", "style", "setup", "trigger", "make", "install", "update", "system"])
        #expect(MenuTree.standard == tree)
    }

    @Test func childrenKeepFileOrder() throws {
        let tree = try MenuTree.parse(DefaultMenu.jsonc)
        let agent = tree.children(of: "agent").map(\.id)
        #expect(agent.first == "agent.ask")
        #expect(agent.contains("agent.default"))
        #expect(!agent.contains("agent.default.claude"))
    }

    @Test func searchMatchesLabelsAndAliasesAndSkipsGroups() throws {
        let tree = try MenuTree.parse(DefaultMenu.jsonc)
        let crash = tree.search("crash").map(\.id)
        #expect(crash.contains("agent.diagnose"))
        let theme = tree.search("tokyo")
        #expect(theme.map(\.id) == ["style.theme.tokyo-night"])
        #expect(tree.search("style").allSatisfy { $0.action != nil })
        #expect(tree.search("").isEmpty)
        #expect(tree.search("NEW app").map(\.id).contains("make.app"))
    }

    @Test func pathGivesBreadcrumbs() throws {
        let tree = try MenuTree.parse(DefaultMenu.jsonc)
        #expect(tree.path(to: "style.theme.tokyo-night") == ["Style", "Theme", "Tokyo Night"])
        #expect(tree.path(to: "") == [])
    }

    @Test func jsoncStripsCommentsButNotStrings() throws {
        let text = """
        // header
        {
          /* block */
          "items": [
            { "id": "a", "label": "http://x // not a comment", "action": "echo \\"/* kept */\\"", },
          ],
        }
        """
        let tree = try MenuTree.parse(text)
        #expect(tree.items.count == 1)
        #expect(tree.items[0].label == "http://x // not a comment")
        #expect(tree.items[0].action == "echo \"/* kept */\"")
    }

    @Test func rejectsDuplicatesAndOrphans() {
        #expect(throws: MenuTree.LoadError.duplicateID("a")) {
            try MenuTree(items: [MenuItem(id: "a", label: "A"), MenuItem(id: "a", label: "B")])
        }
        #expect(throws: MenuTree.LoadError.missingParent("x.y")) {
            try MenuTree(items: [MenuItem(id: "x.y", label: "Y")])
        }
    }

    @Test func everySummonActionInTheDefaultMenuIsARealCommand() throws {
        let tree = try MenuTree.parse(DefaultMenu.jsonc)
        let routes = CommandCatalog.all.map(\.route)
        for item in tree.items {
            guard let action = item.action, action.hasPrefix("summon ") else { continue }
            let words = action.dropFirst("summon ".count).split(separator: " ").map(String.init)
            let matched = routes.contains { route in
                let routeWords = route.split(separator: " ").map(String.init)
                return Array(words.prefix(routeWords.count)) == routeWords
            }
            #expect(matched, "\(item.id): \(action)")
        }
    }

    @Test func makeSomethingStartsEveryAppKindFromItsTemplate() throws {
        let tree = try MenuTree.parse(DefaultMenu.jsonc)
        for kind in ProjectKind.allCases {
            let id = "make.\(kind.rawValue)"
            let action = try #require(tree.items.first { $0.id == id }?.action, "\(id) is missing")
            #expect(action.contains("summon project new <name> --kind \(kind.rawValue)"), "\(id): \(action)")
            #expect(!action.contains("scratch"))
        }
    }

    @Test func withProjectsInjectsMyAppsSubmenu() throws {
        let base = try MenuTree.parse(DefaultMenu.jsonc)
        let projects = [
            Project(name: "my-tool", kind: .cli, path: "/path/to/my-tool", created: Date()),
            Project(name: "my-widget", kind: .menubar, path: "/path/to/my-widget", created: Date())
        ]
        let tree = base.withProjects(projects)
        #expect(tree.children(of: nil).contains(where: { $0.id == "apps" && $0.label == "My Apps" }))
        let appChildren = tree.children(of: "apps")
        #expect(appChildren.count == 2)
        #expect(appChildren.map(\.id) == ["apps.my-tool", "apps.my-widget"])
        #expect(tree.path(to: "apps.my-tool") == ["My Apps", "my-tool"])
        let searchResults = tree.search("my-widget")
        #expect(searchResults.first?.id == "apps.my-widget")
    }
}
