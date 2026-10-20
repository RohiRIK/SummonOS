import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SummonCore

/// `summon project shots <name>`: build the app, open it, capture its real UI by window id (menu bar panel or main
/// window), save `docs/screenshots/*.png`, add them to the README, commit. `summon showcase`: the gallery of all apps.
enum ShotCommands {
    @MainActor
    static func shots(_ name: String, _ context: Context, commit: Bool = true) async throws -> [String] {
        guard let project = try ProjectStore(paths: context.paths).load().projects.first(where: { $0.name == name }) else {
            throw CLIError("No project \(name) (summon project list)")
        }
        let folder = URL(fileURLWithPath: project.path)
        let shotsDir = folder.appendingPathComponent("docs/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
        var images: [String] = []
        var cliHelp: String?

        switch project.kind {
        case .menubar, .app:
            let app = try bundle(folder, context)
            let exec = ProjectName.pascal(project.name)
            // Menu bar apps from the template draw their own panel (`--screenshot`, light and dark): clean, and it
            // works when the menu bar is full and the icon is hidden. Older apps and window apps: the live window.
            let binary = (app as NSString).appendingPathComponent("Contents/MacOS/\(exec)")
            let rendered = ["panel-light.png", "panel-dark.png"]
            // At most 20 s: an app made before the template had `--screenshot` just launches and never exits.
            if project.kind == .menubar, run(binary, ["--screenshot", shotsDir.path], within: 20),
               rendered.allSatisfy({ FileManager.default.fileExists(atPath: shotsDir.appendingPathComponent($0).path) }) {
                images += rendered.map { "docs/screenshots/\($0)" }
            } else {
                let file = shotsDir.appendingPathComponent(project.kind == .menubar ? "panel.png" : "window.png")
                try await capture(app: app, executable: exec, menuBar: project.kind == .menubar, to: file)
                images.append("docs/screenshots/\(file.lastPathComponent)")
            }
        case .cli:
            var buildOptions = ProcessOptions()
            buildOptions.timeout = 1800
            let cache = context.paths.home.appendingPathComponent("Library/Caches/macplugins/\(project.name)/build").path
            let build = ["build", "-c", "release", "--package-path", folder.path, "--scratch-path", cache]
            _ = try Shell.runSync("/usr/bin/swift", build, options: buildOptions)
            let bin = try Shell.runSync("/usr/bin/swift", build + ["--show-bin-path"], options: buildOptions)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let candidates = [project.name, ProjectName.pascal(project.name)].map { (bin as NSString).appendingPathComponent($0) }
            guard let tool = candidates.first(where: FileManager.default.isExecutableFile) else { throw CLIError("No built tool in \(bin)") }
            cliHelp = try? Shell.runSync(tool, ["--help"])
        case .screensaver:
            throw CLIError("Screensavers are not captured yet: open it in System Settings › Screen Saver and take the picture there.")
        }

        let readme = folder.appendingPathComponent("README.md")
        let text = (try? String(contentsOf: readme, encoding: .utf8)) ?? "# \(project.name)\n"
        try ProjectShowcase.updateReadme(text, images: images, cliHelp: cliHelp).write(to: readme, atomically: true, encoding: .utf8)

        if commit, let git = context.git, FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) {
            _ = try? Shell.runSync(git, ["-C", folder.path, "add", "README.md", "docs/screenshots"])
            _ = try? Shell.runSync(git, ["-C", folder.path, "commit", "-q", "-m", "docs: screenshots"])
        }
        return images
    }

    /// Runs a program, stopping it after `seconds`; true when it exited 0 in time.
    static func run(_ path: String, _ arguments: [String], within seconds: TimeInterval) -> Bool {
        var options = ProcessOptions()
        options.timeout = seconds
        options.terminateDescendantsOnExit = true
        return (try? ProcessExecutor.runSync(path, arguments, options: options).status) == 0
    }

    /// The template's `scripts/bundle.sh` prints the .app path last.
    static func bundle(_ folder: URL, _ context: Context) throws -> String {
        let script = folder.appendingPathComponent("scripts/bundle.sh").path
        guard FileManager.default.isExecutableFile(atPath: script) else { throw CLIError("No scripts/bundle.sh in \(folder.path)") }
        var options = ProcessOptions()
        options.timeout = 1800
        options.directory = folder
        let output = try Shell.runSync("/bin/bash", [script], options: options)
        guard let last = output.split(separator: "\n").last.map(String.init) else { throw CLIError("bundle.sh printed nothing") }
        return last.hasPrefix("/") ? last : folder.appendingPathComponent(last).path
    }

    /// Opens the app, waits for its UI, captures it, quits it. Needs Screen Recording (and Accessibility for a menu
    /// bar panel) for whatever runs Summon: the terminal or the agent.
    @MainActor
    static func capture(app: String, executable: String, menuBar: Bool, to file: URL) async throws {
        _ = try Shell.runSync("/usr/bin/open", ["-n", app])
        var pid: Int32 = 0
        for _ in 0..<40 where pid == 0 {
            try await Task.sleep(for: .milliseconds(250))
            pid = NSWorkspace.shared.runningApplications.first { $0.executableURL?.path.hasPrefix(app) == true }?.processIdentifier ?? 0
        }
        guard pid != 0 else { throw CLIError("\(app) did not start") }
        defer { kill(pid, SIGTERM) }
        try await Task.sleep(for: .seconds(2))
        if menuBar {
            let click = "tell application \"System Events\" to tell (first process whose unix id is \(pid)) to click menu bar item 1 of menu bar 2"
            do {
                _ = try Shell.runSync("/usr/bin/osascript", ["-e", click])
            } catch {
                throw CLIError("Could not open the menu bar panel: allow Accessibility for this terminal in System Settings › Privacy & Security")
            }
            try await Task.sleep(for: .seconds(1))
        }
        guard let (window, bounds) = window(of: pid, menuBar: menuBar) else {
            throw CLIError("No window to capture: allow Screen Recording for this terminal in System Settings › Privacy & Security")
        }
        // Only this window, on whichever display it is, even if something covers it; never the whole screen.
        do {
            try await captureWindow(window, size: bounds.size, to: file)
        } catch {
            FileHandle.standardError.write(Data("ScreenCaptureKit: \(error)\n".utf8))
            _ = try? Shell.runSync("/usr/sbin/screencapture", ["-x", "-o", "-l\(window)", file.path])
        }
        guard FileManager.default.fileExists(atPath: file.path) else { throw CLIError("screencapture wrote nothing (Screen Recording permission?)") }
    }

    /// ScreenCaptureKit: one window by id, at the display's pixel scale, as PNG.
    @MainActor
    static func captureWindow(_ id: CGWindowID, size: CGSize, to file: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CLIError("window \(id) not shareable") }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CLIError("could not encode the screenshot")
        }
        try png.write(to: file, options: .atomic)
    }

    /// The panel (above normal windows) for a menu bar app, else the largest normal window.
    static func window(of pid: Int32, menuBar: Bool) -> (CGWindowID, CGRect)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        func area(_ w: [String: Any]) -> Double {
            let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return (b["Width"] ?? 0) * (b["Height"] ?? 0)
        }
        let candidates = mine.filter { w in
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            return (menuBar ? layer > 0 && layer < 1000 : layer == 0) && area(w) > 100 * 100
        }
        guard let best = candidates.max(by: { area($0) < area($1) }), let id = best[kCGWindowNumber as String] as? CGWindowID else { return nil }
        let b = best[kCGWindowBounds as String] as? [String: Double] ?? [:]
        return (id, CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0))
    }

    /// `summon showcase [--open]`: `~/Summon/Showcase/index.html`.
    static func showcase(_ context: Context, open: Bool) throws -> URL {
        let page = context.paths.summonHome.appendingPathComponent("Showcase/index.html")
        let entries = try ProjectStore(paths: context.paths).load().projects.map { project -> ProjectShowcase.Entry in
            let folder = URL(fileURLWithPath: project.path)
            let readme = (try? String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8)) ?? ""
            let shots = folder.appendingPathComponent("docs/screenshots")
            let images = ((try? FileManager.default.contentsOfDirectory(atPath: shots.path)) ?? [])
                .filter { $0.hasSuffix(".png") }.sorted()
                .map { relative(from: page.deletingLastPathComponent(), to: shots.appendingPathComponent($0)) }
            return ProjectShowcase.Entry(project: project, summary: ProjectShowcase.summary(fromReadme: readme), images: images)
        }
        try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProjectShowcase.html(entries).write(to: page, atomically: true, encoding: .utf8)
        if open { _ = try? Shell.runSync("/usr/bin/open", [page.path]) }
        return page
    }

    /// `../Apps/x/docs/screenshots/a.png` from `~/Summon/Showcase`; an absolute file URL when outside ~/Summon.
    static func relative(from base: URL, to file: URL) -> String {
        let root = base.deletingLastPathComponent().standardizedFileURL.path + "/"
        let path = file.standardizedFileURL.path
        return path.hasPrefix(root) ? "../" + path.dropFirst(root.count) : "file://" + path
    }
}
