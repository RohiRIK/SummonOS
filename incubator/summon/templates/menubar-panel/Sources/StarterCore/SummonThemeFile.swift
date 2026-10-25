import Foundation

/// The Summon theme this Mac uses: `~/.config/summon/current-theme` names a slug, and
/// `~/.config/summon/themes/<slug>/theme.json` holds its colors. `load()` is nil when no Summon theme is set,
/// and the app then keeps the system colors.
public struct SummonThemeFile: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public var red, green, blue: Double

        public init(red: Double, green: Double, blue: Double) {
            (self.red, self.green, self.blue) = (red, green, blue)
        }
    }

    public var slug: String
    /// The theme's colors by name (`background`, `foreground`, `accent`, `accent2`, `muted`, ...).
    public var colors: [String: RGB]

    public static var defaultConfig: URL {
        // The real home, also inside a sandbox (a screensaver's home is its container).
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/summon", isDirectory: true)
    }

    public static func load(config: URL = defaultConfig) -> SummonThemeFile? {
        guard let raw = try? String(contentsOf: config.appendingPathComponent("current-theme"), encoding: .utf8) else { return nil }
        let slug = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The slug becomes a path component: letters, digits and dashes only.
        guard !slug.isEmpty, slug.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let file = config.appendingPathComponent("themes/\(slug)/theme.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(slug: slug, json: data)
    }

    public static func parse(slug: String, json: Data) -> SummonThemeFile? {
        struct Raw: Decodable { var colors: [String: String] }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: json) else { return nil }
        return SummonThemeFile(slug: slug, colors: raw.colors.compactMapValues(rgb(hex:)))
    }

    /// `#rrggbb` or `rrggbb` to 0...1 components.
    public static func rgb(hex: String) -> RGB? {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return RGB(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// Yields when the theme may have changed (`summon theme set` rewrites `current-theme`). Finishes at once
    /// when the config folder does not exist.
    public static func changes(config: URL = defaultConfig) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let descriptor = open(config.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }
            // The folder, not the file: the file is replaced on every write, which ends a watch on it.
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                                   queue: .global(qos: .utility))
            source.setEventHandler { continuation.yield() }
            source.setCancelHandler { close(descriptor) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }
}
