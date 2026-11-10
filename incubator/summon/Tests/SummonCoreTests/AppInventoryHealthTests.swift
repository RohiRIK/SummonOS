import Foundation
import Testing
@testable import SummonCore

@Suite("App inventory health")
struct AppInventoryHealthTests {
    @Test func mixedFindingsHaveMatchingCountsAndPromptTargets() throws {
        let summary = AppInventoryHealth(
            projects: [project("panel", .menubar), project("tool", .cli), project("good", .app)],
            themes: [theme("broken"), theme("review")],
            artJobs: [art("unfinished"), art("optional")],
            appHealth: [
                "panel": finding(.warning, "PANEL_BUILD_DEFECT"),
                "tool": finding(.advisory, "TOOL_REVIEW_ONLY"),
                "good": finding(.healthy, "APP_HEALTHY_ONLY"),
            ],
            themeHealth: [
                "broken": finding(.error, "THEME_MISSING_FILE"),
                "review": finding(.advisory, "THEME_PALETTE_REVIEW"),
            ],
            artJobHealth: [
                "unfinished": finding(.warning, "ART_MISSING_OUTPUT"),
                "optional": finding(.advisory, "ART_OPTIONAL_REVIEW"),
            ]
        )
        let repairs: [AppSectionCategory: String] = [
            .panel: "PANEL_BUILD_DEFECT", .themes: "THEME_MISSING_FILE", .art: "ART_MISSING_OUTPUT",
        ]
        #expect(summary.repairCount == 3)
        #expect(summary.advisoryCount == 3)
        #expect(Set(summary.entries.filter { $0.health.needsRepair }.map(\.id)) == Set([
            AppSectionCategory.panel.itemID(for: "panel"),
            AppSectionCategory.themes.itemID(for: "broken"),
            AppSectionCategory.art.itemID(for: "unfinished"),
        ]))
        let prompt = try #require(summary.repairPrompt)
        let root = try #require(summary.health(forMenuID: "apps"))
        #expect(root.level == .error)
        #expect(root.fixPrompt == prompt)
        for category in AppSectionCategory.allCases {
            let aggregate = try #require(summary.health(forMenuID: category.menuID))
            let categoryRepairs = summary.entries.filter { $0.category == category && $0.health.needsRepair }
            #expect(summary.repairCount(in: category) == categoryRepairs.count)
            #expect(summary.advisoryCount(in: category) == summary.entries.filter {
                $0.category == category && $0.health.level == .advisory
            }.count)
            #expect(aggregate.needsRepair == !categoryRepairs.isEmpty)
            for (targetCategory, sentinel) in repairs {
                #expect(occurrences(sentinel, in: prompt) == 1)
                #expect(occurrences(sentinel, in: aggregate.fixPrompt ?? "") == (targetCategory == category ? 1 : 0))
            }
        }
        for sentinel in ["TOOL_REVIEW_ONLY", "APP_HEALTHY_ONLY", "THEME_PALETTE_REVIEW", "ART_OPTIONAL_REVIEW"] {
            #expect(!prompt.contains(sentinel))
        }
        for entry in summary.entries {
            #expect(summary.health(forMenuID: entry.id) == entry.health)
        }
    }

    @Test func sameNameAcrossCategoriesRemainsDistinct() throws {
        let summary = AppInventoryHealth(
            projects: [project("shared", .menubar), project("shared", .cli)],
            themes: [theme("shared")], artJobs: [art("shared")],
            appHealth: ["shared": finding(.warning, "PROJECT_DEFECT")],
            themeHealth: ["shared": finding(.error, "THEME_DEFECT")],
            artJobHealth: ["shared": finding(.warning, "ART_DEFECT")]
        )
        #expect(summary.entries.count == 4)
        #expect(summary.repairCount == 4)
        #expect(Set(summary.entries.map(\.id)) == Set([
            AppSectionCategory.panel.itemID(for: "shared"),
            AppSectionCategory.cli.itemID(for: "shared"),
            AppSectionCategory.themes.itemID(for: "shared"),
            AppSectionCategory.art.itemID(for: "shared"),
        ]))
        let prompt = try #require(summary.repairPrompt)
        #expect(occurrences("PROJECT_DEFECT", in: prompt) == 2)
        #expect(occurrences("THEME_DEFECT", in: prompt) == 1)
        #expect(occurrences("ART_DEFECT", in: prompt) == 1)
    }

    @Test func duplicatesAndStaleHealthCannotInflateTargets() throws {
        let summary = AppInventoryHealth(
            projects: [project("one", .app), project("one", .app), project("unchecked", .cli)],
            themes: [theme("one"), theme("one")], artJobs: [art("one"), art("one")],
            appHealth: ["one": finding(.warning, "APP_DEFECT"), "stale": finding(.error, "STALE_APP")],
            themeHealth: ["one": finding(.advisory, "REVIEW_ONLY"), "stale": finding(.error, "STALE_THEME")],
            artJobHealth: ["one": finding(.error, "ART_DEFECT"), "stale": finding(.error, "STALE_ART")]
        )
        #expect(summary.entries.count == 3)
        #expect(summary.repairCount == 2)
        #expect(summary.advisoryCount == 1)
        #expect(summary.health(forMenuID: AppSectionCategory.cli.itemID(for: "unchecked")) == nil)
        #expect(summary.health(forMenuID: "unknown") == nil)
        let prompt = try #require(summary.repairPrompt)
        for sentinel in ["APP_DEFECT", "ART_DEFECT"] {
            #expect(occurrences(sentinel, in: prompt) == 1)
        }
        for category in AppSectionCategory.allCases {
            #expect(summary.health(forMenuID: category.itemID(for: "stale")) == nil)
        }
        for sentinel in ["STALE_APP", "STALE_THEME", "STALE_ART", "REVIEW_ONLY"] {
            #expect(!prompt.contains(sentinel))
        }
    }

    @Test func adviceOnlyNeverOffersRepairs() throws {
        let summary = AppInventoryHealth(
            themes: [theme("review")],
            themeHealth: ["review": finding(.advisory, "PALETTE_REVIEW_ONLY")]
        )
        #expect(summary.repairCount == 0)
        #expect(summary.advisoryCount == 1)
        #expect(summary.repairPrompt == nil)
        #expect(summary.health(forMenuID: "apps")?.level == .advisory)
        #expect(summary.health(forMenuID: AppSectionCategory.themes.menuID)?.level == .advisory)
        for id in ["apps"] + AppSectionCategory.allCases.map(\.menuID) {
            #expect(try #require(summary.health(forMenuID: id)).fixPrompt == nil)
        }
    }

    @Test func repairWithoutPromptUsesNamedDiagnosticAndEncodedArtIdentity() throws {
        let name = "Night sky / study"
        let health = ItemHealth(level: .error, badge: "Missing", detail: "MISSING_RENDER_SENTINEL")
        let summary = AppInventoryHealth(artJobs: [art(name)], artJobHealth: [name: health])
        let entry = try #require(summary.entries.first)
        #expect(entry.category == .art)
        #expect(entry.key == name)
        #expect(entry.name == name)
        #expect(entry.id == AppSectionCategory.art.itemID(for: name))
        #expect(summary.health(forMenuID: entry.id) == health)
        let prompt = try #require(summary.repairPrompt)
        #expect(prompt.contains(name))
        #expect(occurrences("MISSING_RENDER_SENTINEL", in: prompt) == 1)
    }

    @Test func uncheckedInventoryDoesNotInventCheckedEntries() {
        let empty = AppInventoryHealth()
        let unchecked = AppInventoryHealth(projects: [project("pending", .screensaver)])
        #expect(unchecked.entries.isEmpty)
        #expect(unchecked.repairCount == 0)
        #expect(unchecked.advisoryCount == 0)
        #expect(unchecked.repairPrompt == nil)
        #expect(unchecked.health(forMenuID: "apps") != empty.health(forMenuID: "apps"))
        #expect(unchecked.health(forMenuID: "apps") != ItemHealth.healthy)
        #expect(unchecked.health(forMenuID: AppSectionCategory.screensaver.menuID) != ItemHealth.healthy)
    }

    private func finding(_ level: ItemHealth.Level, _ sentinel: String) -> ItemHealth {
        ItemHealth(level: level, badge: "Finding", detail: sentinel, fixPrompt: sentinel)
    }

    private func project(_ name: String, _ kind: ProjectKind) -> Project {
        Project(name: name, kind: kind, path: "/inventory/\(name)", created: Date(timeIntervalSince1970: 0))
    }

    private func art(_ name: String) -> ArtJob {
        ArtJob(name: name, path: "/art/\(name)", images: [], kind: .general)
    }

    private func theme(_ slug: String) -> Theme {
        Theme(name: slug, slug: slug, appearance: "dark", colors: Theme.Colors(
            background: "#101010", foreground: "#eeeeee", accent: "#6080ff", accent2: "#ff6080",
            muted: "#808080", selection: "#303040", cursor: "#eeeeee",
            borderActive: "#6080ff", borderInactive: "#404040"
        ), terminal: Array(repeating: "#202020", count: 16), font: "Mono", wallpapers: [])
    }

    private func occurrences(_ sentinel: String, in text: String) -> Int {
        text.components(separatedBy: sentinel).count - 1
    }
}
