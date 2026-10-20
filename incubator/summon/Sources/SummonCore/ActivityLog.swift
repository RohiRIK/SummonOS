import Foundation

/// Activity events as plain log lines (`time  LEVEL  source  message  key=value`), for the log view,
/// copying, and handing lines to an agent.
public enum ActivityLog {
    public enum Level: String, Sendable {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    public static let defaultQuestion = "Look at these Summon activity log lines. Explain what happened and fix anything that went wrong."
    /// Lines handed to an agent at most; the newest are kept.
    public static let askLimit = 50

    public static func level(_ event: ActivityEvent) -> Level {
        if event.kind == EventKind.taskFailed { return .error }
        guard event.category == .problem else { return .info }
        return event.kind == "hang" ? .warn : .error
    }

    public static func source(_ event: ActivityEvent) -> String {
        event.category.rawValue
    }

    /// Title, then the first detail line and setting changes, on one line.
    public static func message(_ event: ActivityEvent) -> String {
        var parts = [clean(event.title)]
        if let detail = event.detail.map(clean), !detail.isEmpty { parts.append(detail) }
        parts += event.changes.map { "\(clean($0.id)) \(clean($0.from ?? "unset"))→\(clean($0.to))" }
        return parts.joined(separator: "  ")
    }

    /// What the simple log shows: the title, plus setting changes. Details stay in the tooltip and the agent prompt.
    public static func summary(_ event: ActivityEvent) -> String {
        let title = clean(event.title)
        let changes = event.changes.map { change -> String in
            let values = "\(short(change.from ?? "unset")) → \(short(change.to))"
            // "Changed dock.autohide" already names the setting.
            return title.contains(change.id) ? values : "\(clean(change.id)) \(values)"
        }
        return changes.isEmpty ? title : title + ": " + changes.joined(separator: ", ")
    }

    /// File paths shrink to their last two parts (`catppuccin/1-portal.jpg`); other values stay as they are.
    public static func short(_ value: String) -> String {
        let text = clean(value)
        guard text.hasPrefix("/") || text.hasPrefix("~/") else { return text }
        let parts = text.split(separator: "/")
        return parts.count > 2 ? parts.suffix(2).joined(separator: "/") : text
    }

    /// Every agent start also logs a checkpoint; showing both doubles the log for no news. Undos stay.
    public static func isShown(_ event: ActivityEvent) -> Bool {
        event.kind != "checkpoint"
    }

    public static func fields(_ event: ActivityEvent, home: String = NSHomeDirectory()) -> String {
        event.refs.keys.sorted().map { key in
            var value = clean(event.refs[key] ?? "")
            if !home.isEmpty, value.hasPrefix(home) { value = "~" + value.dropFirst(home.count) }
            return "\(key)=\(value)"
        }.joined(separator: " ")
    }

    public static func line(_ event: ActivityEvent, timeZone: TimeZone = .current) -> String {
        let head = [
            timestamp(event.date, timeZone: timeZone),
            level(event).rawValue.padding(toLength: 5, withPad: " ", startingAt: 0),
            source(event).padding(toLength: 10, withPad: " ", startingAt: 0),
            message(event),
        ].joined(separator: "  ")
        let tail = fields(event)
        return tail.isEmpty ? head : head + "  " + tail
    }

    /// Lines oldest first, whatever order `events` came in.
    public static func transcript(_ events: [ActivityEvent], timeZone: TimeZone = .current) -> String {
        events.sorted { $0.date < $1.date }.map { line($0, timeZone: timeZone) }.joined(separator: "\n")
    }

    /// The prompt for "ask the agent about these lines": the question, then the newest `askLimit` lines.
    public static func askPrompt(question: String, events: [ActivityEvent], timeZone: TimeZone = .current) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let newest = Array(events.sorted { $0.date < $1.date }.suffix(askLimit))
        return (trimmed.isEmpty ? defaultQuestion : trimmed)
            + "\n\nSummon activity log (oldest first):\n"
            + transcript(newest, timeZone: timeZone)
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// One printable line: newlines and tabs become spaces; control, bidi and zero-width characters go.
    /// Crash process names, prompts and paths are untrusted.
    public static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\t" || scalar == "\r" {
                scalars.append(" ")
            } else {
                switch scalar.properties.generalCategory {
                case .control, .format: continue
                default: scalars.append(scalar)
                }
            }
        }
        return String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
