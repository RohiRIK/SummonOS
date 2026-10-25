import Foundation
import StarterCore
import Testing

@Suite struct SummonThemeFileTests {
    func config(slug: String?, json: String?) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("themes/night"), withIntermediateDirectories: true)
        if let slug { try Data("\(slug)\n".utf8).write(to: folder.appendingPathComponent("current-theme")) }
        if let json { try Data(json.utf8).write(to: folder.appendingPathComponent("themes/night/theme.json")) }
        return folder
    }

    @Test func readsTheCurrentThemesColors() throws {
        let folder = try config(slug: "night", json: ##"{"name": "Night", "colors": {"accent": "#ff8000", "muted": "bad"}}"##)
        let theme = try #require(SummonThemeFile.load(config: folder))
        #expect(theme.slug == "night")
        #expect(theme.colors["accent"] == SummonThemeFile.RGB(red: 1, green: 128.0 / 255, blue: 0))
        #expect(theme.colors["muted"] == nil)
    }

    @Test func noThemeMeansSystemColors() throws {
        #expect(SummonThemeFile.load(config: try config(slug: nil, json: nil)) == nil)
        #expect(SummonThemeFile.load(config: try config(slug: "night", json: "not json")) == nil)
        #expect(SummonThemeFile.load(config: try config(slug: "../night", json: #"{"colors": {}}"#)) == nil)
    }

    @Test func parsesHex() {
        #expect(SummonThemeFile.rgb(hex: "000000") == SummonThemeFile.RGB(red: 0, green: 0, blue: 0))
        #expect(SummonThemeFile.rgb(hex: "#fff") == nil)
        #expect(SummonThemeFile.rgb(hex: "#gggggg") == nil)
    }
}
