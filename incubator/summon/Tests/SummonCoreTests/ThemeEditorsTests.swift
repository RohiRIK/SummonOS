import Foundation
import Testing
@testable import SummonCore

@Suite("Theme the whole Mac: accent, VS Code/Cursor and Neovim")
struct ThemeEditorsTests {
    static func theme(accent: String) throws -> Theme {
        var theme = try Theme.decode(Data(sampleThemeJSON.utf8))
        theme.colors.accent = accent
        return theme
    }

    @Test func accentMapsToTheNearestMacOSAccent() throws {
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#FF3B30")) == 0)
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#FF9500")) == 1)
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#FFCC00")) == 2)
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#34C759")) == 3)
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#7AA2F7")) == 4)
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#8B5CF6")) == 5)
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#FF2D92")) == 6)
        #expect(ThemeCompiler.accentIndex(try Self.theme(accent: "#808080")) == -1)
    }

    @Test func vscodeThemeAndManifestAreValidJSON() throws {
        let theme = try Theme.decode(Data(sampleThemeJSON.utf8))
        let body = try #require(try JSONSerialization.jsonObject(with: Data(ThemeCompiler.vscodeTheme(theme).utf8)) as? [String: Any])
        #expect(body["name"] as? String == "Summon")
        #expect(body["type"] as? String == "dark")
        let colors = try #require(body["colors"] as? [String: String])
        #expect(colors["editor.background"] == "#0B0D17")
        #expect(colors["focusBorder"] == "#8B5CF6")
        #expect((body["tokenColors"] as? [Any])?.isEmpty == false)
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(ThemeCompiler.vscodePackage(theme).utf8)) as? [String: Any])
        let themes = try #require((manifest["contributes"] as? [String: Any])?["themes"] as? [[String: String]])
        #expect(themes.first?["label"] == "Summon")
        #expect(themes.first?["uiTheme"] == "vs-dark")
        #expect(themes.first?["path"] == "./themes/summon.json")
    }

    @Test func neovimColorschemeIsNamedSummon() throws {
        let lua = ThemeCompiler.nvim(try Theme.decode(Data(sampleThemeJSON.utf8)))
        #expect(lua.contains(#"vim.g.colors_name = "summon""#))
        #expect(lua.contains(##"hi("Normal", { fg = "#E6E1F5", bg = "#0B0D17" })"##))
        #expect(lua.contains(#"vim.o.background = "dark""#))
    }
}
