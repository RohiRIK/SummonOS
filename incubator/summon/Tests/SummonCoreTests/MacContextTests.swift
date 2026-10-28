import Foundation
import Testing
@testable import SummonCore

@Suite("summon context: the Mac snapshot agents read")
struct MacContextTests {
    static let sample = MacContext(
        generated: Date(timeIntervalSince1970: 1_800_000_000),
        system: .init(model: "Mac16,7", chip: "Apple M4 Pro", memoryGB: 48, macOS: "27.0.1 (26A434)",
                      hostname: "Studio", uptimeHours: 3.9),
        power: .init(battery: 74, charging: false, onAC: false, lowPowerMode: false, thermal: "nominal"),
        storage: [.init(name: "Macintosh HD", path: "/", freeGB: 796, totalGB: 994)],
        network: .init(online: true, primaryInterface: "en0", vpn: false),
        displays: [.init(width: 1728, height: 1117, scale: 2, main: true)],
        apps: .init(frontmost: "Ghostty", frontmostBundleID: "com.mitchellh.ghostty", windowTitle: "~/code",
                    running: ["Finder", "Ghostty"]),
        appearance: .init(dark: true, accent: "blue", wallpaper: "~/Pictures/wall.heic"),
        permissions: .init(accessibility: true, screenRecording: false, fullDiskAccess: false),
        agents: .init(defaultAgent: "claude", installed: ["claude", "codex"]),
        recentCrashes: 2,
        hidden: [])

    @Test func renderIsOneShortLinePerSection() {
        let text = Self.sample.render()
        let lines = text.split(separator: "\n")
        // Small enough for a SessionStart hook or a prompt preamble.
        #expect(lines.count <= 16)
        #expect(text.count < 1_500)
        #expect(text.contains("- Mac: Mac16,7, Apple M4 Pro, 48 GB RAM, macOS 27.0.1 (26A434), name \"Studio\", up 3.9 h"))
        #expect(text.contains("- Power: battery 74%, on battery, thermal nominal"))
        #expect(text.contains("- Network: online via en0, VPN off"))
        #expect(text.contains("- Frontmost: Ghostty (com.mitchellh.ghostty), window \"~/code\""))
        #expect(text.contains("- Problems: 2 crashes or hangs in the last day"))
        #expect(!text.contains("Hidden by the user"))
    }

    @Test func spokenIsOneShortSentenceForSiri() {
        #expect(Self.sample.spoken == "Battery 74%. 796 GB free. 2 crashes or hangs in the last day.")
        #expect(MacContext(generated: Date(), hidden: []).spoken == "Your Mac looks fine.")
    }

    @Test func hiddenFieldsAreRemovedAndNamed() {
        let hidden = Self.sample.hiding(ContextField.allCases)
        #expect(hidden.system?.hostname == nil)
        #expect(hidden.apps?.windowTitle == nil)
        #expect(hidden.apps?.running == nil)
        #expect(hidden.appearance?.wallpaper == nil)
        #expect(hidden.storage?.first?.path == nil)
        #expect(hidden.apps?.frontmost == "Ghostty")
        #expect(hidden.hidden == ["hostname", "paths", "running-apps", "window-title"])
        let text = hidden.render()
        #expect(!text.contains("Studio"))
        #expect(!text.contains("wall.heic"))
        #expect(text.contains("- Hidden by the user: hostname, paths, running-apps, window-title"))
    }

    @Test func onlyKeepsTheNamedSectionsAndRejectsTypos() throws {
        let trimmed = try Self.sample.only(["power", "crashes"])
        #expect(trimmed.power == Self.sample.power)
        #expect(trimmed.recentCrashes == 2)
        #expect(trimmed.system == nil && trimmed.apps == nil && trimmed.storage == nil)
        #expect(throws: ContextError.unknownSection("powr")) { try Self.sample.only(["powr"]) }
    }

    @Test func hookOutputMatchesEachAgentsFormat() throws {
        let text = Self.sample.render()
        #expect(Self.sample.hookOutput(for: "claude") == text)
        #expect(Self.sample.hookOutput(for: "codex") == text)
        let cursor = try JSONDecoder().decode(JSONValue.self, from: Data(Self.sample.hookOutput(for: "cursor").utf8))
        #expect(cursor["additional_context"]?.string == text)
        let agy = try JSONDecoder().decode(JSONValue.self, from: Data(Self.sample.hookOutput(for: "agy").utf8))
        #expect(agy["injectSteps"]?.array?.first?["systemMessage"]?["systemMessage"]?.string == text)
    }

    @Test func accentNamesFollowTheGlobalDomainValues() {
        #expect(MacContext.accentName(nil) == "multicolor")
        #expect(MacContext.accentName(-1) == "graphite")
        #expect(MacContext.accentName(4) == "blue")
        #expect(MacContext.accentName(42) == "multicolor")
    }

    @Test func hiddenFieldsPersistAndUnknownNamesAreDropped() throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        let store = AgentSettingsStore(paths: paths)
        var settings = store.load()
        #expect(settings.hiddenContext.isEmpty)
        settings.setContext(.windowTitle, visible: false)
        settings.setContext(.hostname, visible: false)
        try store.save(settings)
        #expect(store.load().hiddenContext == [.hostname, .windowTitle])
        settings.setContext(.hostname, visible: true)
        #expect(settings.hiddenContext == [.windowTitle])
        try writeFile(#"{"agents": {}, "hiddenContext": ["paths", "from-the-future"]}"#, to: paths.agentSettingsFile)
        #expect(try store.loadValidated().hiddenContext == [.paths])
        #expect(AgentSettingsCommand.context(.paths, visible: false) == ["context", "hide", "paths"])
    }

    @Test @MainActor func liveProbeReadsThisMac() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let context = MacContextProbe.live(paths: paths, tools: ToolLocator(searchPath: [], isExecutable: { _ in false }),
                                           hidden: [.hostname])
        let system = try #require(context.system)
        #expect(system.memoryGB > 0)
        #expect(system.macOS.first?.isNumber == true)
        #expect(system.hostname == nil)
        #expect(context.agents?.installed == [])
        #expect(context.hidden == ["hostname"])
    }
}
