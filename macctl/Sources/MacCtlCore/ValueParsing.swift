import Foundation

// Parsing CLI text and validating profile values against a setting's `ValueType`.
//
// Callers pass the setting id so errors arrive as `MacCtlError.invalidValue(id:value:reason:)`
// ready to print. `validate` is the pure check (returns a reason or nil); `coerce` normalizes
// (int → double for double settings, `~` expansion for paths) and then validates.

extension ValueType {
    /// Parses CLI text into a typed, normalized, validated value.
    /// - bool accepts true/false, yes/no, on/off, 1/0 (any case).
    /// - int / double are range-checked; double accepts integer text.
    /// - enumeration is an exact, case-sensitive match.
    /// - path expands a leading `~` and must end up absolute.
    public func parse(_ text: String, id: String) throws(MacCtlError) -> Value {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw: Value
        switch self {
        case .bool:
            switch trimmed.lowercased() {
            case "true", "yes", "on", "1": raw = .bool(true)
            case "false", "no", "off", "0": raw = .bool(false)
            default:
                throw MacCtlError.invalidValue(
                    id: id, value: text, reason: "expected a boolean: true/false, yes/no, on/off, 1/0")
            }
        case .int:
            guard let i = Int(trimmed) else {
                throw MacCtlError.invalidValue(id: id, value: text, reason: "expected an integer")
            }
            raw = .int(i)
        case .double:
            guard let d = Double(trimmed), d.isFinite else {
                throw MacCtlError.invalidValue(id: id, value: text, reason: "expected a number")
            }
            raw = .double(d)
        case .string:
            raw = .string(text)
        case .enumeration:
            raw = .string(trimmed)
        case .path:
            raw = .string(trimmed)
        }
        return try check(normalize(raw), id: id, shownAs: text)
    }

    /// Normalizes and validates a value that arrived typed (for example from a profile file).
    public func coerce(_ value: Value, id: String) throws(MacCtlError) -> Value {
        try check(normalize(value), id: id, shownAs: value.description)
    }

    /// Int → double for double settings, `~` expansion for paths. Never fails; values of the wrong
    /// kind pass through unchanged so `validate` can report them.
    public func normalize(_ value: Value) -> Value {
        switch (self, value) {
        case (.double, .int(let i)): .double(Double(i))
        case (.path, .string(let s)): .string(Self.expandTilde(s))
        default: value
        }
    }

    /// Why `value` is not acceptable for this type, or nil when it is.
    public func validate(_ value: Value) -> String? {
        switch (self, value) {
        case (.bool, .bool):
            return nil
        case (.int(let lo, let hi), .int(let i)):
            return Self.rangeReason(i, lo: lo, hi: hi)
        case (.double(let lo, let hi), .double(let d)):
            guard d.isFinite else { return "must be a finite number" }
            return Self.rangeReason(d, lo: lo, hi: hi)
        case (.double(let lo, let hi), .int(let i)):
            return Self.rangeReason(Double(i), lo: lo, hi: hi)
        case (.string, .string):
            return nil
        case (.enumeration(let options), .string(let s)):
            return options.contains(s) ? nil : "must be one of: \(options.joined(separator: ", "))"
        case (.path, .string(let s)):
            return Self.expandTilde(s).hasPrefix("/") ? nil : "must be an absolute path or start with ~"
        default:
            return "expected \(expectation), got \(value.kindName)"
        }
    }

    /// Human phrase for what this type accepts ("an integer", "one of: a, b").
    public var expectation: String {
        switch self {
        case .bool: "a boolean"
        case .int: "an integer"
        case .double: "a number"
        case .string: "a string"
        case .enumeration(let options): "one of: \(options.joined(separator: ", "))"
        case .path: "a path"
        }
    }

    // MARK: - Private

    private func check(_ normalized: Value, id: String, shownAs: String) throws(MacCtlError) -> Value {
        if let reason = validate(normalized) {
            throw MacCtlError.invalidValue(id: id, value: shownAs, reason: reason)
        }
        return normalized
    }

    static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return NSString(string: path).expandingTildeInPath
    }

    private static func rangeReason<T: Comparable & CustomStringConvertible>(
        _ v: T, lo: T?, hi: T?
    ) -> String? {
        switch (lo, hi) {
        case let (l?, h?):
            return (v < l || v > h) ? "must be between \(l) and \(h)" : nil
        case let (l?, nil):
            return v < l ? "must be at least \(l)" : nil
        case let (nil, h?):
            return v > h ? "must be at most \(h)" : nil
        case (nil, nil):
            return nil
        }
    }
}

extension Value {
    /// Kind name for error messages.
    var kindName: String {
        switch self {
        case .bool: "a boolean"
        case .int: "an integer"
        case .double: "a number"
        case .string: "a string"
        }
    }

    /// Equality that treats `.int(2)` and `.double(2.0)` as the same value
    /// (`defaults` and JSON round trips can turn one into the other).
    func sameValue(as other: Value) -> Bool {
        switch (self, other) {
        case (.int(let a), .double(let b)): Double(a) == b
        case (.double(let a), .int(let b)): a == Double(b)
        default: self == other
        }
    }
}
