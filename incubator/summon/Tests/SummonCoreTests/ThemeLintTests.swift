import Foundation
import Testing
@testable import SummonCore

@Suite("Theme colors: OKLCH accepted, palettes checked")
struct ThemeLintTests {
    @Test func oklchConvertsToHex() throws {
        #expect(OKLCH.hex(fromCSS: "oklch(1 0 0)") == "#FFFFFF")
        #expect(OKLCH.hex(fromCSS: "oklch(0 0 0)") == "#000000")
        #expect(OKLCH.hex(fromCSS: "#1e1e2e") == "#1E1E2E")
        // Catppuccin blue #89b4fa is oklch(0.766 0.111 259.9) (independent Python computation).
        let blue = try #require(HexColor("#89b4fa"))
        let (l, c, h) = OKLCH.from(blue)
        #expect(abs(l - 0.766) < 0.005 && abs(c - 0.111) < 0.005 && abs(h - 259.9) < 0.5)
        #expect(OKLCH.hex(fromCSS: "oklch(0.5 0.1)") == nil)
    }

    @Test func themesMayBeWrittenInOKLCH() throws {
        var json = sampleThemeJSON
        json = json.replacingOccurrences(of: "\"#0B0D17\"", with: "\"oklch(0.15 0.03 270)\"")
        let theme = try Theme.decode(Data(json.utf8))
        #expect(theme.colors.background.hasPrefix("#") && theme.colors.background.count == 7)
        #expect(ThemeCompiler.ghostty(theme).contains("background = \(theme.colors.background.dropFirst())"))
    }

    @Test func lintFlagsAnInvisibleAccentAndOneHueTerminal() throws {
        var theme = try Theme.decode(Data(sampleThemeJSON.utf8))
        #expect(ThemeLint.problems(theme).filter { $0.severity == .error }.isEmpty)
        theme.colors.accent = theme.colors.background
        theme.terminal[1] = theme.terminal[4]   // "red" is blue
        let problems = ThemeLint.problems(theme)
        #expect(problems.contains { $0.severity == .error && $0.message.contains("accent") })
        #expect(problems.contains { $0.message.contains("red") && $0.message.contains("hue") })
    }
}
