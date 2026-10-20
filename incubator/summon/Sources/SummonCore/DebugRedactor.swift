import Foundation

/// Best-effort minimization for exported diagnostics; arbitrary log text still needs human review.
public enum DebugRedactor {
    public static func redact(_ text: String, home: String) -> String {
        var result = home.isEmpty ? text : text.replacingOccurrences(of: home, with: "~")
        let rules: [(String, String)] = [
            (#"(?im)^(\s*(?:Serial Number[^:]*|Hardware UUID|Provisioning UDID)\s*:)\s*[^\r\n]+$"#, "$1 [redacted]"),
            (#"(?im)\bAuthorization\s*[:=]\s*[^\r\n]+"#, "Authorization: [redacted]"),
            (#"(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)\s*[:=]\s*[\"']?[^\s,;\"']+"#, "[credential redacted]"),
            (#"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"#, "[hardware address redacted]"),
        ]
        for (pattern, replacement) in rules {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            result = expression.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        return result
    }
}
