import Foundation
import SummonCore

/// `summon panel [--close]`: opens or closes the menu bar panel through `summon://panel[/close]`.
/// `open -g` keeps the frontmost app frontmost, so Summon is never activated (panel spec A1, A6, C5, C6).
enum PanelCommand {
    static let usage = "Usage: summon panel [--close]"

    static func run(_ args: inout Arguments, _ context: Context) async throws {
        let route: PanelRoute = args.flag("--close") ? .close : .open
        guard args.isEmpty else { throw CLIError(usage) }
        _ = try await context.runner("/usr/bin/open", ["-g", route.url])
    }
}
