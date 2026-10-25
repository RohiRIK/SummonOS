import Foundation
import Testing
@testable import SummonCore

@Suite("Agent hotkey: what is on screen becomes the agent's first message")
struct ScreenContextTests {
    @Test func promptNamesTheAppPageAndSelection() throws {
        let screen = ScreenContext(app: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs",
                                   selectedText: "line one\nline two", pageTitle: "Swift", pageURL: "https://swift.org")
        let prompt = try #require(screen.prompt())
        #expect(prompt.contains("- App: Safari (com.apple.Safari), window \"Docs\""))
        #expect(prompt.contains("- Page: \"Swift\" https://swift.org"))
        #expect(prompt.contains("  > line one\n  > line two"))
        #expect(prompt.hasSuffix("Wait for it; do not act on this yet."))
        #expect(ScreenContext().prompt() == nil)
    }

    @Test func longSelectionsAreCut() throws {
        let screen = ScreenContext(app: "Notes", selectedText: String(repeating: "a", count: ScreenContext.selectionLimit + 50))
        let prompt = try #require(screen.prompt())
        #expect(prompt.contains("(first \(ScreenContext.selectionLimit) characters)"))
        #expect(!prompt.contains(String(repeating: "a", count: ScreenContext.selectionLimit + 1)))
    }

    @Test func scriptsOnlyForBrowsersAndFinderAndOnlyWhenAllowed() {
        #expect(ScreenContext.script(for: "com.apple.Safari", hidden: [])?.contains("com.apple.Safari") == true)
        #expect(ScreenContext.script(for: "net.imput.helium", hidden: [])?.contains("active tab") == true)
        #expect(ScreenContext.script(for: "com.apple.finder", hidden: [])?.contains("selection") == true)
        #expect(ScreenContext.script(for: "com.apple.Safari", hidden: [.browserPage]) == nil)
        #expect(ScreenContext.script(for: "com.apple.finder", hidden: [.finderSelection]) == nil)
        #expect(ScreenContext.script(for: "com.mitchellh.ghostty", hidden: []) == nil)
        #expect(ScreenContext.script(for: nil, hidden: []) == nil)
    }

    @Test func scriptOutputFillsThePageOrTheFinderSelection() {
        var browser = ScreenContext(app: "Chrome", bundleID: "com.google.Chrome")
        browser.apply(scriptOutput: "Pull request #78\nhttps://github.com/RohiRIK/SummonOS/pull/78\n")
        #expect(browser.pageTitle == "Pull request #78")
        #expect(browser.pageURL == "https://github.com/RohiRIK/SummonOS/pull/78")
        var empty = ScreenContext(app: "Chrome", bundleID: "com.google.Chrome")
        empty.apply(scriptOutput: "missing value\n")
        #expect(empty.pageURL == nil)
        var finder = ScreenContext(app: "Finder", bundleID: "com.apple.finder")
        finder.apply(scriptOutput: "/Users/me/a.txt\n/Users/me/b/\n")
        #expect(finder.finderSelection == ["/Users/me/a.txt", "/Users/me/b/"])
    }

    @Test func newFieldsCanBeHiddenAndDoNotTouchTheMacSnapshot() {
        #expect(ContextField.allCases.map(\.rawValue).suffix(3) == ["selected-text", "browser-page", "finder-selection"])
        #expect(MacContextTests.sample.hiding([.selectedText, .browserPage]).apps == MacContextTests.sample.apps)
    }
}
