import Foundation
import Testing
@testable import SummonCore

@Suite("Themes")
struct ThemeTests {
    func sample() throws -> Theme {
        try Theme.decode(Data(sampleThemeJSON.utf8))
    }

    @Test func decodesAndValidates() throws {
        let theme = try sample()
        #expect(theme.slug == "summon-night")
        #expect(theme.isDark)
        #expect(theme.colors.borderActive == "#8B5CF6")
        #expect(theme.source == "original")
    }

    @Test func rejectsBadThemes() throws {
        let shortPalette = sampleThemeJSON.replacingOccurrences(of: "\"#414868\", ", with: "")
        #expect(throws: Theme.ValidationError.terminalCount(15)) { try Theme.decode(Data(shortPalette.utf8)) }
        let badColor = sampleThemeJSON.replacingOccurrences(of: "#0B0D17", with: "navy")
        #expect(throws: Theme.ValidationError.badColor(field: "background", value: "navy")) { try Theme.decode(Data(badColor.utf8)) }
        let badSlug = sampleThemeJSON.replacingOccurrences(of: "\"summon-night\"", with: "\"../evil\"")
        #expect(throws: Theme.ValidationError.badSlug("../evil")) { try Theme.decode(Data(badSlug.utf8)) }
    }

    @Test func hexColorParsesAndMixes() throws {
        let black = try #require(HexColor("#000000"))
        let white = try #require(HexColor("FFFFFF"))
        #expect(black.mixed(with: white, 0.5).hash == "#808080")
        #expect(black.mixed(with: white, 0).hash == "#000000")
        #expect(try #require(HexColor("#0b0d17")).bare == "0B0D17")
        #expect(HexColor("#12345") == nil)
        #expect(HexColor("#GGGGGG") == nil)
    }

    @Test func ghosttyConfig() throws {
        let text = ThemeCompiler.ghostty(try sample())
        #expect(text.contains("background = 0B0D17\n"))
        #expect(text.contains("foreground = E6E1F5\n"))
        #expect(text.contains("palette = 0=#15172A\n"))
        #expect(text.contains("palette = 15=#E6E1F5\n"))
        #expect(text.contains("font-family = \"JetBrainsMono Nerd Font\"\n"))
        #expect(text.components(separatedBy: "palette = ").count == 17)
    }

    @Test func bordersArguments() throws {
        let args = ThemeCompiler.bordersArguments(try sample())
        #expect(args.contains("active_color=0xff8B5CF6"))
        #expect(args.contains("inactive_color=0xff2A2440"))
    }

    @Test func claudeThemeIsValidJSON() throws {
        let text = ThemeCompiler.claudeTheme(try sample())
        let object = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["base"] as? String == "dark")
        let overrides = try #require(object["overrides"] as? [String: String])
        #expect(overrides["claude"] == "#8B5CF6")
        #expect(overrides["error"] == "#F7768E")
        #expect(overrides.values.allSatisfy { HexColor($0) != nil })
    }

    @Test func storeActivatesAndLists() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let store = ThemeStore(paths: paths)
        try writeFile(sampleThemeJSON, to: paths.themes.appendingPathComponent("summon-night/theme.json"))
        try writeFile("{ broken", to: paths.themes.appendingPathComponent("broken/theme.json"))
        #expect(store.all().map(\.slug) == ["summon-night"])
        let theme = try #require(store.theme("summon-night"))
        let written = try store.activate(theme)
        #expect(written.count == 4)
        #expect(store.currentSlug() == "summon-night")
        #expect(store.wallpaperURL(theme)?.lastPathComponent == "wallpaper-1.jpg")
        #expect(store.wallpaperURL(theme, index: 3) == nil)
        let borders = paths.generated.appendingPathComponent("bordersrc").path
        #expect(FileManager.default.isExecutableFile(atPath: borders))
    }
}
