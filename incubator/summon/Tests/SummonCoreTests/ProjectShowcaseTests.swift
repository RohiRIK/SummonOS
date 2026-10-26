import Foundation
import Testing
@testable import SummonCore

@Suite("Project screenshots and the showcase")
struct ProjectShowcaseTests {
    let project = Project(name: "mac-battery", kind: .menubar, path: "/u/a/Summon/Apps/mac-battery",
                          created: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func readmeSectionIsAddedOnceAndReplacedAfter() {
        let readme = "# Mac Battery\n\nShows the battery.\n\n## Build\n\nscripts/check.sh\n"
        let first = ProjectShowcase.updateReadme(readme, images: ["docs/screenshots/panel.png"], cliHelp: nil)
        #expect(first.contains("<!-- summon:screenshots -->"))
        #expect(first.contains("![Mac Battery: panel](docs/screenshots/panel.png)"))
        #expect(first.range(of: "## Screenshots")!.lowerBound < first.range(of: "## Build")!.lowerBound)
        let second = ProjectShowcase.updateReadme(first, images: ["docs/screenshots/panel.png", "docs/screenshots/settings.png"], cliHelp: nil)
        #expect(second.components(separatedBy: "<!-- summon:screenshots -->").count == 2)
        #expect(second.contains("settings.png"))
        let cli = ProjectShowcase.updateReadme(readme, images: [], cliHelp: "USAGE: battery [--json]")
        #expect(cli.contains("```text\nUSAGE: battery [--json]\n```"))
    }

    @Test func showcaseListsEveryAppWithItsPictures() {
        let html = ProjectShowcase.html([
            .init(project: project, summary: "Shows the battery & <time> left.", images: ["../Apps/mac-battery/docs/screenshots/panel.png"]),
        ])
        #expect(html.contains("<title>Summon Showcase</title>"))
        #expect(html.contains("mac-battery"))
        #expect(html.contains("Shows the battery &amp; &lt;time&gt; left."))
        #expect(html.contains("src=\"../Apps/mac-battery/docs/screenshots/panel.png\""))
        #expect(html.contains("prefers-color-scheme: dark"))
    }

    @Test func everyRenderedShotIsListedMainSurfaceFirst() {
        let files = ["editor-light.png", "panel-light.png", ".DS_Store", "editor-dark.png", "panel-dark.png"]
        #expect(ProjectShowcase.orderedShots(files, surface: "panel")
                == ["panel-light.png", "panel-dark.png", "editor-light.png", "editor-dark.png"])
        #expect(ProjectShowcase.orderedShots([], surface: "window").isEmpty)
    }

    @Test func summaryIsTheFirstParagraphAfterTheTitle() {
        #expect(ProjectShowcase.summary(fromReadme: "# Mac Battery\n\nShows the battery.\nIn the menu bar.\n\n## Build\n") == "Shows the battery. In the menu bar.")
        #expect(ProjectShowcase.summary(fromReadme: "# X\n\nA panel (`MenuBarExtra`), **fast**.\n") == "A panel (MenuBarExtra), fast.")
    }
}
