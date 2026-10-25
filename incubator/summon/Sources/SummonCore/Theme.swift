import Foundation

/// One theme file (`themes/<slug>/theme.json`): the single source of truth that every target is compiled from.
public struct Theme: Sendable, Equatable, Codable, Identifiable {
    public struct Colors: Sendable, Equatable, Codable {
        public var background: String
        public var foreground: String
        public var accent: String
        public var accent2: String
        public var muted: String
        public var selection: String
        public var cursor: String
        public var borderActive: String
        public var borderInactive: String

        enum CodingKeys: String, CodingKey {
            case background, foreground, accent, accent2, muted, selection, cursor
            case borderActive = "border_active"
            case borderInactive = "border_inactive"
        }
    }

    public var name: String
    public var slug: String
    /// "dark" or "light".
    public var appearance: String
    public var colors: Colors
    /// 16 ANSI colors: black, red, green, yellow, blue, magenta, cyan, white, then the bright set.
    public var terminal: [String]
    public var font: String
    public var wallpapers: [String]
    /// Where the palette came from (for ports of other themes), shown in credits.
    public var source: String?

    public var id: String { slug }
    public var isDark: Bool { appearance != "light" }

    public enum ValidationError: Error, Equatable, Sendable {
        case badSlug(String)
        case badAppearance(String)
        case badColor(field: String, value: String)
        case terminalCount(Int)
        case badText(field: String)
        case badWallpaper(String)
    }

    public func validate() throws {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !slug.isEmpty, slug.allSatisfy({ allowed.contains($0) }) else { throw ValidationError.badSlug(slug) }
        guard appearance == "dark" || appearance == "light" else { throw ValidationError.badAppearance(appearance) }
        for (field, value) in [("name", name), ("font", font)] {
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty,
                  value.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else {
                throw ValidationError.badText(field: field)
            }
        }
        for wallpaper in wallpapers where !Self.isRelativeWallpaper(wallpaper) {
            throw ValidationError.badWallpaper(wallpaper)
        }
        let named: [(String, String)] = [
            ("background", colors.background), ("foreground", colors.foreground), ("accent", colors.accent),
            ("accent2", colors.accent2), ("muted", colors.muted), ("selection", colors.selection),
            ("cursor", colors.cursor), ("border_active", colors.borderActive), ("border_inactive", colors.borderInactive),
        ]
        for (field, value) in named where HexColor(value) == nil {
            throw ValidationError.badColor(field: field, value: value)
        }
        guard terminal.count == 16 else { throw ValidationError.terminalCount(terminal.count) }
        for (index, value) in terminal.enumerated() where HexColor(value) == nil {
            throw ValidationError.badColor(field: "terminal[\(index)]", value: value)
        }
    }

    /// Themes contain decorative data, never absolute paths or references outside their own folder.
    static func isRelativeWallpaper(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), path.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    public static func decode(_ data: Data) throws -> Theme {
        var theme = try JSONDecoder().decode(Theme.self, from: data)
        theme.normalizeColors()
        try theme.validate()
        return theme
    }

    /// `oklch(L C H)` values (how the summon-art skill designs palettes) become `#RRGGBB`, which every target needs.
    mutating func normalizeColors() {
        func fix(_ value: inout String) { if let hex = OKLCH.hex(fromCSS: value) { value = hex } }
        fix(&colors.background); fix(&colors.foreground); fix(&colors.accent); fix(&colors.accent2); fix(&colors.muted)
        fix(&colors.selection); fix(&colors.cursor); fix(&colors.borderActive); fix(&colors.borderInactive)
        for index in terminal.indices { fix(&terminal[index]) }
    }
}

/// `#RRGGBB`.
public struct HexColor: Sendable, Equatable {
    public var red: Int
    public var green: Int
    public var blue: Int

    public init?(_ text: String) {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        red = (value >> 16) & 0xFF
        green = (value >> 8) & 0xFF
        blue = value & 0xFF
    }

    public init(red: Int, green: Int, blue: Int) {
        self.red = max(0, min(255, red))
        self.green = max(0, min(255, green))
        self.blue = max(0, min(255, blue))
    }

    /// Upper-case without `#`.
    public var bare: String { Self.twoDigits(red) + Self.twoDigits(green) + Self.twoDigits(blue) }

    private static func twoDigits(_ value: Int) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return text.count == 1 ? "0" + text : text
    }
    public var hash: String { "#" + bare }

    /// `self` moved `fraction` (0...1) of the way toward `other`, like Omarchy's `mix a b 35%` with the weight on `other`.
    public func mixed(with other: HexColor, _ fraction: Double) -> HexColor {
        let f = max(0, min(1, fraction))
        func channel(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * f).rounded()) }
        return HexColor(red: channel(red, other.red), green: channel(green, other.green), blue: channel(blue, other.blue))
    }
}

/// Writes one theme out to every target. Each target is a small pure function so it can be tested.
public enum ThemeCompiler {
    public static let header = "Generated by `summon theme set`. Do not edit: it is replaced on every theme change."

    /// Included from the user's Ghostty config with `config-file = ~/.config/summon/generated/ghostty.conf`.
    public static func ghostty(_ theme: Theme) -> String {
        var lines = ["# \(header)", "# Theme: \(theme.name)"]
        lines.append("background = \(bare(theme.colors.background))")
        lines.append("foreground = \(bare(theme.colors.foreground))")
        lines.append("cursor-color = \(bare(theme.colors.cursor))")
        lines.append("selection-background = \(bare(theme.colors.selection))")
        lines.append("selection-foreground = \(bare(theme.colors.foreground))")
        for (index, color) in theme.terminal.enumerated() {
            lines.append("palette = \(index)=\(hash(color))")
        }
        let font = theme.font.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        lines.append("font-family = \"\(font)\"")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Included from the user's kitty config with `include ~/.config/summon/generated/kitty.conf`.
    public static func kitty(_ theme: Theme) -> String {
        var lines = ["# \(header)", "# Theme: \(theme.name)"]
        lines.append("background \(hash(theme.colors.background))")
        lines.append("foreground \(hash(theme.colors.foreground))")
        lines.append("cursor \(hash(theme.colors.cursor))")
        lines.append("selection_background \(hash(theme.colors.selection))")
        lines.append("selection_foreground \(hash(theme.colors.foreground))")
        for (index, color) in theme.terminal.enumerated() {
            lines.append("color\(index) \(hash(color))")
        }
        lines.append("font_family \(theme.font)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The macOS accent (`appearance.accent-color`) nearest the theme's accent: by hue, graphite when nearly gray.
    public static func accentIndex(_ theme: Theme) -> Int {
        let c = color(theme.colors.accent)
        let r = Double(c.red) / 255, g = Double(c.green) / 255, b = Double(c.blue) / 255
        let high = max(r, g, b), low = min(r, g, b), span = high - low
        guard high > 0, span / high > 0.2 else { return -1 }
        var hue: Double
        if high == r { hue = (g - b) / span } else if high == g { hue = 2 + (b - r) / span } else { hue = 4 + (r - g) / span }
        hue = (hue * 60).truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        switch hue {
        case ..<15, 345...: return 0
        case ..<45: return 1
        case ..<70: return 2
        case ..<170: return 3
        case ..<250: return 4
        case ..<310: return 5
        default: return 6
        }
    }

    /// A VS Code (and Cursor) color theme named "Summon"; the user selects it once, later themes rewrite it.
    public static func vscodeTheme(_ theme: Theme) -> String {
        let c = theme.colors
        let ansi = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        var colors: [String: String] = [
            "editor.background": hash(c.background), "editor.foreground": hash(c.foreground),
            "editorCursor.foreground": hash(c.cursor), "editor.selectionBackground": hash(c.selection),
            "editorLineNumber.foreground": hash(c.muted), "editorLineNumber.activeForeground": hash(c.foreground),
            "activityBar.background": hash(c.background), "activityBar.foreground": hash(c.accent),
            "sideBar.background": hash(c.background), "sideBar.foreground": hash(c.foreground),
            "statusBar.background": hash(c.background), "statusBar.foreground": hash(c.muted),
            "titleBar.activeBackground": hash(c.background), "titleBar.activeForeground": hash(c.foreground),
            "tab.activeBackground": hash(c.selection), "tab.inactiveBackground": hash(c.background),
            "focusBorder": hash(c.accent), "button.background": hash(c.accent), "button.foreground": hash(c.background),
            "terminal.background": hash(c.background), "terminal.foreground": hash(c.foreground),
        ]
        for (index, value) in theme.terminal.prefix(16).enumerated() {
            colors["terminal.ansi" + (index < 8 ? "" : "Bright") + ansi[index % 8]] = hash(value)
        }
        let term = theme.terminal.map(hash)
        func token(_ scope: [String], _ color: String, italic: Bool = false) -> [String: Any] {
            var settings: [String: Any] = ["foreground": color]
            if italic { settings["fontStyle"] = "italic" }
            return ["scope": scope, "settings": settings]
        }
        let body: [String: Any] = [
            "name": "Summon", "type": theme.isDark ? "dark" : "light", "colors": colors,
            "tokenColors": [
                token(["comment"], hash(c.muted), italic: true),
                token(["keyword", "storage", "keyword.control"], hash(c.accent)),
                token(["string"], term.count > 2 ? term[2] : hash(c.accent2)),
                token(["entity.name.function", "support.function"], hash(c.accent2)),
                token(["constant", "constant.numeric"], term.count > 3 ? term[3] : hash(c.accent)),
                token(["entity.name.type", "support.type"], term.count > 6 ? term[6] : hash(c.accent2)),
            ],
        ]
        return json(body)
    }

    /// The extension manifest that makes `vscodeTheme` show up as "Summon" in VS Code and Cursor.
    public static func vscodePackage(_ theme: Theme) -> String {
        json([
            "name": "summon-theme", "displayName": "Summon", "publisher": "summon", "version": "0.0.1",
            "description": header, "engines": ["vscode": "^1.70.0"], "categories": ["Themes"],
            "contributes": ["themes": [["label": "Summon", "uiTheme": theme.isDark ? "vs-dark" : "vs", "path": "./themes/summon.json"]]],
        ])
    }

    /// `~/.config/nvim/colors/summon.lua`, chosen with `:colorscheme summon`.
    public static func nvim(_ theme: Theme) -> String {
        let c = theme.colors
        let term = theme.terminal.map(hash)
        func at(_ index: Int, _ fallback: String) -> String { term.count > index ? term[index] : hash(fallback) }
        var lines = ["-- \(header)", "-- Theme: \(theme.name)", #"vim.cmd("highlight clear")"#, #"vim.g.colors_name = "summon""#,
                     "vim.o.background = \"\(theme.isDark ? "dark" : "light")\"",
                     "local hi = function(group, opts) vim.api.nvim_set_hl(0, group, opts) end"]
        let groups: [(String, String)] = [
            ("Normal", "fg = \"\(hash(c.foreground))\", bg = \"\(hash(c.background))\""),
            ("Comment", "fg = \"\(hash(c.muted))\", italic = true"),
            ("Statement", "fg = \"\(hash(c.accent))\""), ("Keyword", "fg = \"\(hash(c.accent))\""),
            ("String", "fg = \"\(at(2, c.accent2))\""), ("Function", "fg = \"\(hash(c.accent2))\""),
            ("Constant", "fg = \"\(at(3, c.accent))\""), ("Type", "fg = \"\(at(6, c.accent2))\""),
            ("Visual", "bg = \"\(hash(c.selection))\""), ("CursorLine", "bg = \"\(hash(c.selection))\""),
            ("LineNr", "fg = \"\(hash(c.muted))\""), ("CursorLineNr", "fg = \"\(hash(c.accent))\""),
            ("StatusLine", "fg = \"\(hash(c.foreground))\", bg = \"\(hash(c.selection))\""),
            ("Pmenu", "fg = \"\(hash(c.foreground))\", bg = \"\(hash(c.selection))\""),
            ("Search", "fg = \"\(hash(c.background))\", bg = \"\(hash(c.accent))\""),
            ("WinSeparator", "fg = \"\(hash(c.borderInactive))\""),
        ]
        lines += groups.map { "hi(\"\($0.0)\", { \($0.1) })" }
        lines += term.prefix(16).enumerated().map { "vim.g.terminal_color_\($0.offset) = \"\($0.element)\"" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func json(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// Arguments for JankyBorders: `borders <args…>` (also valid as `bordersrc` lines).
    public static func bordersArguments(_ theme: Theme) -> [String] {
        [
            "active_color=0xff\(bare(theme.colors.borderActive))",
            "inactive_color=0xff\(bare(theme.colors.borderInactive))",
            "width=5.0",
            "style=round",
        ]
    }

    /// A Claude Code custom theme (`~/.claude/themes/summon.json`), same keys as Omarchy's.
    public static func claudeTheme(_ theme: Theme) -> String {
        let c = theme.colors
        let t = theme.terminal
        let bg = color(c.background), fg = color(c.foreground), accent = color(c.accent)
        let red = color(t[1]), green = color(t[2]), yellow = color(t[3]), blue = color(t[4])
        let magenta = color(t[5]), cyan = color(t[6])
        let brightYellow = color(t[11]), brightCyan = color(t[14])
        let overrides: [(String, HexColor)] = [
            ("claude", accent),
            ("claudeShimmer", accent.mixed(with: fg, 0.35)),
            ("text", fg),
            ("inverseText", bg),
            ("inactive", fg.mixed(with: bg, 0.40)),
            ("inactiveShimmer", fg.mixed(with: bg, 0.25)),
            ("subtle", color(c.muted)),
            ("suggestion", cyan),
            ("permission", blue),
            ("permissionShimmer", blue.mixed(with: fg, 0.35)),
            ("remember", yellow),
            ("success", green),
            ("error", red),
            ("warning", yellow),
            ("warningShimmer", yellow.mixed(with: fg, 0.35)),
            ("merged", magenta),
            ("promptBorder", accent),
            ("promptBorderShimmer", accent.mixed(with: fg, 0.35)),
            ("planMode", cyan),
            ("autoAccept", yellow),
            ("bashBorder", brightYellow),
            ("ide", brightCyan),
            ("diffAdded", bg.mixed(with: green, 0.15)),
            ("diffRemoved", bg.mixed(with: red, 0.15)),
            ("diffAddedDimmed", bg.mixed(with: green, 0.08)),
            ("diffRemovedDimmed", bg.mixed(with: red, 0.08)),
            ("diffAddedWord", bg.mixed(with: green, 0.32)),
            ("diffRemovedWord", bg.mixed(with: red, 0.32)),
            ("userMessageBackground", bg.mixed(with: fg, 0.06)),
            ("selectionBg", color(c.selection)),
        ]
        var lines = ["{", "  \"name\": \"Summon\",", "  \"base\": \"\(theme.isDark ? "dark" : "light")\",", "  \"overrides\": {"]
        for (index, pair) in overrides.enumerated() {
            let comma = index == overrides.count - 1 ? "" : ","
            lines.append("    \"\(pair.0)\": \"\(pair.1.hash)\"\(comma)")
        }
        lines.append("  }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func color(_ text: String) -> HexColor {
        HexColor(text) ?? HexColor(red: 255, green: 0, blue: 255)
    }

    private static func bare(_ text: String) -> String { color(text).bare }
    private static func hash(_ text: String) -> String { color(text).hash }
}

/// Reads installed themes and remembers the current one.
public struct ThemeStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    /// Valid themes in `~/.config/summon/themes/*/theme.json`, sorted by name. Broken files are skipped.
    public func all() -> [Theme] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: paths.themes, includingPropertiesForKeys: nil) else { return [] }
        var themes: [Theme] = []
        for dir in dirs {
            let file = dir.appendingPathComponent("theme.json")
            guard let data = try? Data(contentsOf: file), let theme = try? Theme.decode(data) else { continue }
            themes.append(theme)
        }
        return themes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func theme(_ slug: String) -> Theme? {
        all().first { $0.slug == slug }
    }

    public func currentSlug() -> String? {
        TextFile.firstLine(paths.currentThemeFile)
    }

    public func wallpaperURL(_ theme: Theme, index: Int = 0) -> URL? {
        guard (try? theme.validate()) != nil, index >= 0, index < theme.wallpapers.count else { return nil }
        return containedWallpaperURL(theme, index: index)
    }

    private func containedWallpaperURL(_ theme: Theme, index: Int) -> URL? {
        let themes = paths.themes.resolvingSymlinksInPath().standardizedFileURL
        let unresolvedRoot = themes.appendingPathComponent(theme.slug)
        let root = unresolvedRoot.resolvingSymlinksInPath().standardizedFileURL
        guard root.path.hasPrefix(themes.path + "/"), !isUnresolvedLink(unresolvedRoot, resolved: root) else { return nil }
        var wallpaper = root
        // Resolve each existing component: Foundation may leave an entire path unresolved when its final file
        // does not exist yet, even if a parent is a symlink outside the theme.
        for component in theme.wallpapers[index].split(separator: "/") {
            let candidate = wallpaper.appendingPathComponent(String(component))
            wallpaper = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard wallpaper.path.hasPrefix(root.path + "/"), !isUnresolvedLink(candidate, resolved: wallpaper) else { return nil }
        }
        return wallpaper
    }

    private func isUnresolvedLink(_ url: URL, resolved: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil && url.standardizedFileURL.path == resolved.path
    }

    /// Writes `current-theme` and every generated file; returns the files written.
    @discardableResult
    public func activate(_ theme: Theme) throws -> [URL] {
        try theme.validate()
        for index in theme.wallpapers.indices where containedWallpaperURL(theme, index: index) == nil {
            throw Theme.ValidationError.badWallpaper(theme.wallpapers[index])
        }
        let ghostty = paths.generated.appendingPathComponent("ghostty.conf")
        let borders = paths.generated.appendingPathComponent("bordersrc")
        let kitty = paths.generated.appendingPathComponent("kitty.conf")
        let claude = paths.generated.appendingPathComponent("claude-theme.json")
        try TextFile.write(ThemeCompiler.ghostty(theme), to: ghostty)
        try TextFile.write(ThemeCompiler.kitty(theme), to: kitty)
        let bordersScript = "#!/bin/sh\n# \(ThemeCompiler.header)\nborders " + ThemeCompiler.bordersArguments(theme).joined(separator: " ") + "\n"
        try TextFile.write(bordersScript, to: borders)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: borders.path)
        try TextFile.write(ThemeCompiler.claudeTheme(theme), to: claude)
        try TextFile.write(theme.slug + "\n", to: paths.currentThemeFile)
        return [ghostty, kitty, borders, claude, paths.currentThemeFile]
    }
}
