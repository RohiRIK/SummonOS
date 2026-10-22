import Foundation

/// Formats diagnostics into a structured briefing for any coding agent to resolve.
public enum FixPrompt {
    public static func make(
        for checks: [DoctorCheck],
        crashes: [CrashReport] = [],
        skillPath: String? = nil
    ) -> String {
        var lines: [String] = []
        let issueCount = checks.count
        let crashCount = crashes.count
        
        lines.append("Summon diagnosed issues on this Mac that need attention.")
        lines.append("Please investigate, explain the root cause, and apply fixes.")
        lines.append("")
        
        if issueCount > 0 {
            lines.append("## Diagnostic Issues (\(issueCount)):")
            for check in checks {
                let statusLabel = check.status == .fail ? "[FAIL]" : "[WARN]"
                lines.append("• \(statusLabel) \(check.id): \(check.detail)")
                if let fix = check.fix, !fix.isEmpty {
                    lines.append("  Suggested fix: \(fix)")
                }
            }
            lines.append("")
        }
        
        if crashCount > 0 {
            lines.append("## Recent Crash Reports (\(crashCount)):")
            for crash in crashes {
                var desc = "• \(crash.program) (kind: \(crash.kind))"
                if let sig = crash.signal { desc += ", signal: \(sig)" }
                if let exc = crash.exceptionType { desc += ", exception: \(exc)" }
                lines.append(desc)
                lines.append("  Report file: \(crash.file)")
            }
            lines.append("")
        }
        
        lines.append("## Instructions:")
        lines.append("1. Analyze the diagnosed issues in priority order (FAIL first, then WARN, then crashes).")
        lines.append("2. Explain to the user in concise, plain language what needs to be done.")
        lines.append("3. Execute the appropriate fixes, or guide the user if manual permissions are needed.")
        lines.append("4. Finally, run `summon doctor` to confirm that all checks pass.")
        
        if let skillPath, !skillPath.isEmpty {
            lines.append("")
            lines.append("Refer to the summon-mac skill for macOS system guidelines, tools, and conventions:")
            lines.append("  \(skillPath)")
        }
        
        return lines.joined(separator: "\n")
    }
}
