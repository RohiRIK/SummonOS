import Foundation

/// Screenshots in a project's README, and `~/Summon/Showcase/index.html`: a gallery of every app Summon made.
public enum ProjectShowcase {
    static let start = "<!-- summon:screenshots -->"
    static let end = "<!-- /summon:screenshots -->"

    /// Puts (or replaces) a Screenshots section right after the README's first paragraph.
    public static func updateReadme(_ readme: String, images: [String], cliHelp: String?) -> String {
        let title = readme.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) } ?? "App"
        var body = ["## Screenshots", ""]
        for image in images {
            let label = ((image as NSString).lastPathComponent as NSString).deletingPathExtension
            body.append("![\(title): \(label)](\(image))")
            body.append("")
        }
        if let cliHelp {
            body += ["```text", cliHelp.trimmingCharacters(in: .whitespacesAndNewlines), "```", ""]
        }
        let section = ([start] + body + [end]).joined(separator: "\n")

        if let open = readme.range(of: start), let close = readme.range(of: end, range: open.upperBound..<readme.endIndex) {
            return readme.replacingCharacters(in: open.lowerBound..<close.upperBound, with: section)
        }
        // After the title and the first paragraph.
        var lines = readme.components(separatedBy: "\n")
        var index = (lines.firstIndex { $0.hasPrefix("# ") } ?? -1) + 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        lines.insert(contentsOf: ["", section], at: min(index, lines.count))
        return lines.joined(separator: "\n")
    }

    /// The first paragraph after the `# Title` line, joined into one line.
    public static func summary(fromReadme readme: String) -> String {
        let lines = readme.components(separatedBy: "\n")
        var index = (lines.firstIndex { $0.hasPrefix("# ") } ?? -1) + 1
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        var paragraph: [String] = []
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty, !lines[index].hasPrefix("#") {
            paragraph.append(lines[index].trimmingCharacters(in: .whitespaces))
            index += 1
        }
        // Plain text for the page: no Markdown marks.
        return paragraph.joined(separator: " ")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
    }

    public struct Entry: Sendable, Equatable {
        public var project: Project
        public var summary: String
        /// Paths relative to the showcase page.
        public var images: [String]

        public init(project: Project, summary: String, images: [String]) {
            self.project = project
            self.summary = summary
            self.images = images
        }
    }

    public static func html(_ entries: [Entry]) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let cards = entries.map { entry -> String in
            let pictures = entry.images.isEmpty
                ? "<div class=\"empty\">No screenshot yet: summon project shots \(escape(entry.project.name))</div>"
                : entry.images.map { "<img src=\"\(escape($0))\" alt=\"\(escape(entry.project.name))\" loading=\"lazy\">" }.joined()
            let repo = entry.project.repo.map { " · <a href=\"\(escape($0))\">repo</a>" } ?? ""
            return """
                <article>
                  <div class="shots">\(pictures)</div>
                  <h2>\(escape(entry.project.name))</h2>
                  <p class="kind">\(escape(entry.project.kind.title))\(repo)</p>
                  <p>\(escape(entry.summary))</p>
                </article>
                """
        }.joined(separator: "\n")
        return """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Summon Showcase</title>
            <style>
              :root { --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --line: #e5e5ea; }
              @media (prefers-color-scheme: dark) { :root { --bg: #111114; --card: #1c1c20; --text: #f5f5f7; --muted: #98989d; --line: #2c2c31; } }
              * { box-sizing: border-box; }
              body { margin: 0; padding: 40px 24px; background: var(--bg); color: var(--text);
                     font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
              header { max-width: 1100px; margin: 0 auto 28px; }
              h1 { font-size: 28px; margin: 0; } header p { color: var(--muted); margin: 4px 0 0; }
              main { max-width: 1100px; margin: 0 auto; display: grid; gap: 20px; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); }
              article { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
              .shots { display: flex; gap: 8px; overflow-x: auto; background: var(--bg); border-radius: 10px; padding: 12px; min-height: 160px; align-items: center; }
              .shots img { max-height: 280px; max-width: 100%; border-radius: 8px; }
              .empty { color: var(--muted); font-size: 13px; margin: auto; text-align: center; }
              h2 { font-size: 17px; margin: 14px 0 0; } .kind { color: var(--muted); font-size: 13px; margin: 2px 0 8px; }
              a { color: inherit; }
            </style>
            </head>
            <body>
            <header><h1>Summon Showcase</h1><p>\(entries.count) app\(entries.count == 1 ? "" : "s") made with Summon</p></header>
            <main>
            \(cards)
            </main>
            </body>
            </html>

            """
    }
}
