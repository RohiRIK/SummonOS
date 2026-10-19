import Foundation

/// OKLCH ⇄ sRGB, so a theme can be written the way the summon-art skill designs it (`oklch(L C H)`) while every
/// target (Ghostty, kitty, borders, Claude) still gets `#RRGGBB`. Björn Ottosson's OKLab matrices.
public enum OKLCH {
    /// `#RRGGBB` for a `#RRGGBB` or `oklch(L C H)` string (L 0…1 or 0…100%, H in degrees); nil when neither.
    public static func hex(fromCSS text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let color = HexColor(trimmed) { return color.hash }
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("oklch("), lower.hasSuffix(")") else { return nil }
        let inner = lower.dropFirst(6).dropLast().replacingOccurrences(of: "/", with: " ")
        let parts = inner.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard parts.count >= 3 else { return nil }
        let lightness = parts[0].hasSuffix("%") ? Double(parts[0].dropLast()).map { $0 / 100 } : Double(parts[0])
        guard let l = lightness, let c = Double(parts[1]), let h = Double(parts[2].replacingOccurrences(of: "deg", with: "")) else { return nil }
        return toHex(l: l, c: c, h: h).hash
    }

    public static func toHex(l: Double, c: Double, h: Double) -> HexColor {
        let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
        let l1 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m1 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s1 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        let r = 4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1
        let g = -1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1
        let bl = -0.0041960863 * l1 - 0.7034186147 * m1 + 1.7076147010 * s1
        func encode(_ v: Double) -> Int {
            let x = min(max(v, 0), 1)
            let srgb = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return Int((srgb * 255).rounded())
        }
        return HexColor(red: encode(r), green: encode(g), blue: encode(bl))
    }

    /// (L 0…1, C, H degrees) of a color.
    public static func from(_ color: HexColor) -> (Double, Double, Double) {
        func linear(_ v: Int) -> Double {
            let x = Double(v) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        let r = linear(color.red), g = linear(color.green), b = linear(color.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (lightness, sqrt(a * a + bb * bb), hue)
    }
}

/// What makes a theme hard to use, beyond a valid file: text that cannot be read, borders that vanish, a terminal
/// palette whose "red" is not red. `summon theme check` prints these; errors mean the theme should not be set.
public enum ThemeLint {
    public struct Problem: Sendable, Equatable {
        public enum Severity: String, Sendable { case error, warning }
        public var severity: Severity
        public var message: String
    }

    /// WCAG contrast ratio of two colors.
    public static func contrast(_ first: HexColor, _ second: HexColor) -> Double {
        func luminance(_ color: HexColor) -> Double {
            func channel(_ v: Int) -> Double {
                let x = Double(v) / 255
                return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// ANSI 1…6 (and 9…14) hue ranges in OKLCH degrees; generous, so tinted palettes still pass.
    static let hues: [(name: String, ranges: [ClosedRange<Double>])] = [
        ("red", [0...50, 335...360]), ("green", [100...175]), ("yellow", [60...115]),
        ("blue", [215...300]), ("magenta", [285...360, 0...10]), ("cyan", [135...235]),  // aqua (Gruvbox, Everforest) counts
    ]

    public static func problems(_ theme: Theme) -> [Problem] {
        var problems: [Problem] = []
        guard let background = HexColor(theme.colors.background) else { return [Problem(severity: .error, message: "background is not a color")] }
        func check(_ name: String, _ value: String, need: Double, error: Double) {
            guard let color = HexColor(value) else { return }
            let ratio = contrast(color, background)
            if ratio < error {
                problems.append(Problem(severity: .error, message: "\(name) \(value) is \(String(format: "%.1f", ratio)):1 on the background (needs \(need))"))
            } else if ratio < need {
                problems.append(Problem(severity: .warning, message: "\(name) \(value) is \(String(format: "%.1f", ratio)):1 on the background (aim for \(need))"))
            }
        }
        check("foreground", theme.colors.foreground, need: 7, error: 4.5)
        check("accent", theme.colors.accent, need: 3, error: 2)
        check("border_active", theme.colors.borderActive, need: 3, error: 2)
        for (index, value) in theme.terminal.enumerated() where index != 0 && index != 8 {
            check("terminal[\(index)]", value, need: 4.5, error: 2.5)
        }
        for (offset, hue) in hues.enumerated() {
            for index in [offset + 1, offset + 9] where index < theme.terminal.count {
                guard let color = HexColor(theme.terminal[index]) else { continue }
                let (_, chroma, degrees) = OKLCH.from(color)
                if chroma < 0.04 || !hue.ranges.contains(where: { $0.contains(degrees) }) {
                    problems.append(Problem(severity: .warning,
                        message: "terminal[\(index)] should read as \(hue.name) but its hue is \(Int(degrees))° (chroma \(String(format: "%.2f", chroma)))"))
                }
            }
        }
        return problems
    }
}
