import AppKit
import Foundation
import SummonCore

enum ThemeCommands {
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        let store = ThemeStore(paths: context.paths)
        switch args.next() {
        case "list":
            let themes = store.all()
            if args.flag("--json") {
                try context.printJSON(themes)
                return
            }
            guard !themes.isEmpty else {
                throw CLIError("No themes in \(context.paths.themes.path). Copy the repo's themes/ folder there (scripts/install.sh does).")
            }
            let current = store.currentSlug()
            for theme in themes {
                print("\(theme.slug == current ? "*" : " ") \(theme.slug.padding(toLength: max(16, themes.map(\.slug.count).max() ?? 0), withPad: " ", startingAt: 0)) \(theme.name) (\(theme.appearance))")
            }
        case "check":
            // Why a theme does not show in `theme list`: broken files are skipped there, silently.
            guard let slug = args.next() else { throw CLIError("Usage: summon theme check <slug>") }
            let file = context.paths.themes.appendingPathComponent(slug).appendingPathComponent("theme.json")
            guard let data = FileManager.default.contents(atPath: file.path) else { throw CLIError("No \(file.path)") }
            do {
                let theme = try Theme.decode(data)
                let problems = ThemeLint.problems(theme)
                for problem in problems { print("\(problem.severity.rawValue): \(problem.message)") }
                let errors = problems.filter { $0.severity == .error }.count
                if errors > 0 { throw CLIError("\(theme.name): \(errors) problem\(errors == 1 ? "" : "s") to fix before summon theme set") }
                print(problems.isEmpty ? "\(theme.name): valid, contrast and colors fine" : "\(theme.name): valid, \(problems.count) warning\(problems.count == 1 ? "" : "s")")
            } catch let error as Theme.ValidationError {
                throw CLIError("\(file.path): \(error) — colors are #RRGGBB, 16 terminal colors, slug a-z 0-9 -")
            } catch {
                throw CLIError("\(file.path) is not valid JSON (no comments, no trailing commas): \(error.localizedDescription)")
            }
        case "current":
            if let slug = store.currentSlug() { print(slug) }
        case "set":
            let skipWallpaper = args.flag("--no-wallpaper")
            guard let slug = args.next() else { throw CLIError("Usage: summon theme set <slug> [--no-wallpaper]") }
            guard let theme = store.theme(slug) else {
                throw CLIError("No theme \"\(slug)\". See: summon theme list")
            }
            try await apply(theme, store: store, wallpaper: !skipWallpaper, context)
            ActivityCommands.record(LoggedEvent(kind: EventKind.themeSet, title: "Theme: \(theme.name)", refs: ["theme": theme.slug]), context)
        default:
            throw CLIError("Usage: summon theme list|current|set <slug>")
        }
    }

    @MainActor
    static func apply(_ theme: Theme, store: ThemeStore, wallpaper: Bool, _ context: Context) async throws {
        let written = try store.activate(theme)
        print("Theme: \(theme.name)")
        for url in written { print("  wrote \(url.path)") }

        // macOS appearance goes through macctl, so it is snapshotted and undoable.
        if let macctl = context.macctl {
            do {
                _ = try await context.runner(macctl, ["set", "appearance.dark-mode", theme.appearance == "dark" ? "true" : "false"])
                print("  appearance: \(theme.appearance)")
            } catch {
                context.warn("  appearance not changed: \(error)")
            }
        } else {
            print("  appearance unchanged (install macctl to switch light/dark with the theme)")
        }

        if wallpaper, let url = store.wallpaperURL(theme) {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    // Through macctl when installed, so `summon checkpoint undo` restores the old picture.
                    if let macctl = context.macctl {
                        _ = try await context.runner(macctl, ["set", "desktop.wallpaper", url.path, "--json"])
                    } else {
                        for screen in NSScreen.screens {
                            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                        }
                    }
                    print("  wallpaper: \(url.lastPathComponent)")
                } catch {
                    context.warn("  wallpaper not changed: \(error)")
                }
            } else {
                context.warn("  wallpaper missing: \(url.path)")
            }
        }

        // JankyBorders: calling `borders` with arguments updates a running instance; only do it when one runs.
        if let borders = context.tools.find("borders"), (try? await context.runner("/usr/bin/pgrep", ["-x", "borders"])) != nil {
            do {
                try Shell.spawn(borders, ThemeCompiler.bordersArguments(theme))
                print("  borders: recolored")
            } catch {
                context.warn("  borders not recolored: \(error)")
            }
        }

        // Claude Code reads custom themes from ~/.claude/themes; choosing it stays the user's call (/theme).
        let claudeDir = context.paths.home.appendingPathComponent(".claude", isDirectory: true)
        if FileManager.default.fileExists(atPath: claudeDir.path) {
            let target = claudeDir.appendingPathComponent("themes/summon.json")
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(ThemeCompiler.claudeTheme(theme).utf8).write(to: target, options: .atomic)
                print("  Claude Code theme: \(target.path)")
            } catch {
                context.warn("  Claude Code theme not written: \(error)")
            }
        }

        let failures = await HookRunner(paths: context.paths, runner: context.runner).run(.themeSet, arguments: [theme.slug])
        for failure in failures { context.warn("  hook failed: \(failure)") }
        print("Ghostty picks up the new colors on its next config reload (⌘⇧,) when its config has:")
        print("  config-file = \(context.paths.generated.appendingPathComponent("ghostty.conf").path)")
    }
}
