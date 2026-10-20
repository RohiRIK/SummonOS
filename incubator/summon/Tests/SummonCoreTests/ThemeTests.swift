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

    @Test func kittyConfig() throws {
        let text = ThemeCompiler.kitty(try sample())
        #expect(text.contains("background #0B0D17\n"))
        #expect(text.contains("foreground #E6E1F5\n"))
        #expect(text.contains("color0 #15172A\n"))
        #expect(text.contains("color15 #E6E1F5\n"))
        #expect(text.contains("font_family JetBrainsMono Nerd Font\n"))
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
        #expect(written.count == 5)
        #expect(store.currentSlug() == "summon-night")
        #expect(store.wallpaperURL(theme)?.lastPathComponent == "wallpaper-1.jpg")
        #expect(store.wallpaperURL(theme, index: 3) == nil)
        let borders = paths.generated.appendingPathComponent("bordersrc").path
        #expect(FileManager.default.isExecutableFile(atPath: borders))
    }

    @Test func rejectsDecorativeConfigInjectionBeforeWriting() throws {
        let store = ThemeStore(paths: SummonPaths(home: try makeTempHome()))
        for field in ["name", "font"] {
            for payload in ["normal\ncommand = /usr/bin/true", "normal\rshell /usr/bin/true", "normal\0hidden", "normal\u{2028}command = /usr/bin/true"] {
                var object = try #require(JSONSerialization.jsonObject(with: Data(sampleThemeJSON.utf8)) as? [String: Any])
                object[field] = payload
                let data = try JSONSerialization.data(withJSONObject: object)
                #expect(throws: Theme.ValidationError.self) { try Theme.decode(data) }
                var theme = try sample()
                if field == "name" { theme.name = payload } else { theme.font = payload }
                #expect(throws: Theme.ValidationError.self) { try store.activate(theme) }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: store.paths.generated.path))
    }

    @Test func ghosttyEscapesQuotedFontNames() throws {
        var theme = try sample()
        theme.font = "The \"Quoted\" \\ Font"
        #expect(ThemeCompiler.ghostty(theme).contains("font-family = \"The \\\"Quoted\\\" \\\\ Font\"\n"))
    }

    @Test func wallpapersStayInsideTheirTheme() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let store = ThemeStore(paths: paths)
        for path in ["../private.jpg", "/tmp/private.jpg", "sub/../../private.jpg", "sub/./image.jpg", "image\n.jpg"] {
            var theme = try sample()
            theme.wallpapers = [path]
            #expect(throws: Theme.ValidationError.self) { try theme.validate() }
            #expect(store.wallpaperURL(theme) == nil)
        }
        var theme = try sample()
        theme.wallpapers = ["nested/image.jpg"]
        try theme.validate()
        let root = paths.themes.appendingPathComponent(theme.slug)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = paths.home.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("nested").path, withDestinationPath: outside.path)
        #expect(store.wallpaperURL(theme) == nil)
        #expect(throws: Theme.ValidationError.self) { try store.activate(theme) }
    }

    @Test func themeFolderSymlinksCannotEscapeThemesDirectory() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let store = ThemeStore(paths: paths)
        let theme = try sample()
        try FileManager.default.createDirectory(at: paths.themes, withIntermediateDirectories: true)
        let outside = paths.home.appendingPathComponent("themes-other")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: paths.themes.appendingPathComponent(theme.slug).path, withDestinationPath: outside.path)
        #expect(store.wallpaperURL(theme) == nil)
        #expect(throws: Theme.ValidationError.self) { try store.activate(theme) }
    }
}
