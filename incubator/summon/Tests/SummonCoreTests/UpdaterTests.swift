import Foundation
import Testing
@testable import SummonCore

@Suite("summon update: channels, versions, checksums")
struct UpdaterTests {
    static let releasesJSON = """
    [
      {"tag_name": "edge", "draft": false, "prerelease": true,
       "assets": [{"name": "SHA256SUMS"}, {"name": "summonos-0.2.0-edge.abc1234-macos-universal.zip"}]},
      {"tag_name": "v0.10.0", "draft": true, "prerelease": true, "assets": []},
      {"tag_name": "v0.2.0", "draft": false, "prerelease": true, "assets": []},
      {"tag_name": "v0.1.0", "draft": false, "prerelease": true, "assets": []},
      {"tag_name": "not-a-version", "draft": false, "prerelease": false, "assets": []}
    ]
    """

    @Test func versionsFollowSemVerPrecedence() throws {
        func v(_ text: String) throws -> ReleaseVersion { try #require(ReleaseVersion(text)) }
        #expect(try v("0.1.0") < v("0.2.0"))
        #expect(try v("0.9.0") < v("0.10.0"))
        #expect(try v("0.1.0-edge.abc1234") < v("0.1.0"))
        #expect(try v("0.1.0") < v("0.2.0-edge.abc1234"))
        #expect(try v("1.0.0-alpha") < v("1.0.0-alpha.1"))
        #expect(try v("1.0.0-alpha.2") < v("1.0.0-alpha.10"))
        #expect(try v("1.0.0-1") < v("1.0.0-alpha"))
        #expect(try v("0.1.0-edge.abc1234") == v("0.1.0-edge.abc1234"))
        for bad in ["", "0.1", "0.1.0.0", "v0.1.0", "0.1.0-", "0.1.0-edge..x", "0.1.0-../x", "0.a.0"] {
            #expect(ReleaseVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func stablePicksTheHighestPublishedTagAndNeverEdge() throws {
        let release = try Updater.pick(Data(Self.releasesJSON.utf8), channel: .stable)
        #expect(release == UpdateRelease(tag: "v0.2.0", version: "0.2.0"))
        #expect(release.zipURL == "https://github.com/RohiRIK/SummonOS/releases/download/v0.2.0/summonos-0.2.0-macos-universal.zip")
        #expect(release.sumsURL == "https://github.com/RohiRIK/SummonOS/releases/download/v0.2.0/SHA256SUMS")
    }

    @Test func edgeReadsItsVersionFromTheZipName() throws {
        let release = try Updater.pick(Data(Self.releasesJSON.utf8), channel: .edge)
        #expect(release == UpdateRelease(tag: "edge", version: "0.2.0-edge.abc1234"))
        #expect(release.zipURL.hasSuffix("/download/edge/summonos-0.2.0-edge.abc1234-macos-universal.zip"))
    }

    @Test func missingChannelsAndBadJSONAreErrors() {
        let onlyEdge = #"[{"tag_name": "edge", "assets": [{"name": "summonos-0.1.0-edge.1-macos-universal.zip"}]}]"#
        #expect(throws: UpdateError.noRelease(.stable)) { try Updater.pick(Data(onlyEdge.utf8), channel: .stable) }
        let noEdge = #"[{"tag_name": "v0.1.0"}]"#
        #expect(throws: UpdateError.noRelease(.edge)) { try Updater.pick(Data(noEdge.utf8), channel: .edge) }
        let hostileEdge = #"[{"tag_name": "edge", "assets": [{"name": "summonos-../../x-macos-universal.zip"}]}]"#
        #expect(throws: UpdateError.noRelease(.edge)) { try Updater.pick(Data(hostileEdge.utf8), channel: .edge) }
        #expect(throws: UpdateError.self) { try Updater.pick(Data("rate limited".utf8), channel: .stable) }
    }

    @Test func stableUpdatesOnlyForwardEdgeOnAnyDifference() {
        #expect(Updater.isAvailable(current: "0.1.0", latest: "0.2.0", channel: .stable))
        #expect(!Updater.isAvailable(current: "0.2.0", latest: "0.2.0", channel: .stable))
        #expect(!Updater.isAvailable(current: "0.3.0-edge.abc", latest: "0.2.0", channel: .stable))
        // Leaving edge for the release it led up to.
        #expect(Updater.isAvailable(current: "0.2.0-edge.abc", latest: "0.2.0", channel: .stable))
        #expect(Updater.isAvailable(current: "0.2.0-edge.abc", latest: "0.2.0-edge.def", channel: .edge))
        #expect(Updater.isAvailable(current: "0.2.0", latest: "0.2.0-edge.def", channel: .edge))
        #expect(!Updater.isAvailable(current: "0.2.0-edge.def", latest: "0.2.0-edge.def", channel: .edge))
        #expect(!Updater.isAvailable(current: "0.1.0", latest: "garbage", channel: .edge))
    }

    @Test func channelIsRememberedAndDefaultsToStable() throws {
        let store = UpdateChannelStore(paths: SummonPaths(home: try makeTempHome()))
        #expect(store.load() == .stable)
        try store.save(.edge)
        #expect(store.load() == .edge)
        #expect(store.file.path.hasSuffix(".config/summon/defaults/channel"))
    }

    @Test func appChecksForUpdatesUntilTurnedOff() throws {
        let store = AutoUpdateStore(paths: SummonPaths(home: try makeTempHome()))
        #expect(store.load())
        try store.save(false)
        #expect(!store.load())
        try store.save(true)
        #expect(store.load())
        #expect(store.file.path.hasSuffix(".config/summon/defaults/update-check"))
    }

    @Test func checksumsParseBothShasumModes() {
        let digest = String(repeating: "ab", count: 32)
        #expect(Updater.expectedDigest("\(digest)  a.zip\n", file: "a.zip") == digest)
        #expect(Updater.expectedDigest("\(digest.uppercased()) *a.zip\n", file: "a.zip") == digest)
        #expect(Updater.expectedDigest("\(digest)  b.zip\n", file: "a.zip") == nil)
        #expect(Updater.expectedDigest("short  a.zip\n", file: "a.zip") == nil)
    }

    /// SHA256SUMS that matches the zip, as the release workflow writes it.
    static let honestSums: @Sendable (Data) -> String = { data in
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? data.write(to: file)
        return "\((try? Updater.sha256(of: file)) ?? "")  summonos-0.2.0-macos-universal.zip\n"
    }

    /// A fake GitHub: curl writes the asset files, ditto unpacks a package, env records the installer hand-off.
    func fakeGitHub(_ log: CallLog, zip: Data, sums: @escaping @Sendable (Data) -> String, layout: Bool = true) -> Runner {
        { path, arguments in
            await log.add([path] + arguments)
            switch (path as NSString).lastPathComponent {
            case "curl":
                if let index = arguments.firstIndex(of: "-o") {
                    let out = URL(fileURLWithPath: arguments[index + 1])
                    try (out.lastPathComponent == "SHA256SUMS" ? Data(sums(zip).utf8) : zip).write(to: out)
                    return ""
                }
                return UpdaterTests.releasesJSON
            case "ditto":
                guard layout else { return "" }
                let package = URL(fileURLWithPath: arguments[3]).appendingPathComponent("summonos-0.2.0")
                try writeFile("#!/bin/bash\n", to: package.appendingPathComponent("Summon.app/Contents/MacOS/summon"), executable: true)
                try writeFile("#!/bin/bash\n", to: package.appendingPathComponent("bin/macctl"), executable: true)
                try writeFile("#!/bin/bash\n", to: package.appendingPathComponent("scripts/install.sh"), executable: true)
                return ""
            default:
                return "Installed."
            }
        }
    }

    @Test func installVerifiesThenHandsOffToTheStagedInstaller() async throws {
        let work = try makeTempHome()
        let log = CallLog()
        let zip = Data("a release".utf8)
        let runner = fakeGitHub(log, zip: zip, sums: Self.honestSums)
        let updater = Updater(runner: runner, current: "0.1.0")
        let check = try await updater.check(.stable)
        #expect(check.available)
        #expect(try await updater.install(check.release, work: work) == "Installed.")
        let calls = await log.calls
        #expect(calls.map { ($0[0] as NSString).lastPathComponent } == ["curl", "curl", "curl", "ditto", "env"])
        let package = work.appendingPathComponent("unpacked/summonos-0.2.0").path
        #expect(calls[4] == ["/usr/bin/env", "SUMMONOS_APP_SOURCE=\(package)/Summon.app",
                             "SUMMONOS_MACCTL_SOURCE=\(package)/bin/macctl", "/bin/bash", "\(package)/scripts/install.sh"])
    }

    @Test func checkFallsBackToGHWhenTheAnonymousAPIIsBlocked() async throws {
        let log = CallLog()
        let runner = fakeRunner(log, responses: ["curl": nil, "gh": Self.releasesJSON])
        let check = try await Updater(runner: runner, current: "0.1.0", gh: "/opt/homebrew/bin/gh").check(.stable)
        #expect(check.release.version == "0.2.0")
        #expect(await log.calls.last == ["/opt/homebrew/bin/gh", "api", "repos/RohiRIK/SummonOS/releases?per_page=30"])
        // Without gh the curl failure is the answer.
        await #expect(throws: UpdateError.self) { try await Updater(runner: runner, current: "0.1.0").check(.stable) }
    }

    @Test func installRefusesAChecksumMismatchBeforeUnpacking() async throws {
        let log = CallLog()
        let runner = fakeGitHub(log, zip: Data("tampered".utf8)) { _ in
            "\(String(repeating: "0", count: 64))  summonos-0.2.0-macos-universal.zip\n"
        }
        let release = UpdateRelease(tag: "v0.2.0", version: "0.2.0")
        await #expect(throws: UpdateError.checksumMismatch("summonos-0.2.0-macos-universal.zip")) {
            try await Updater(runner: runner, current: "0.1.0").install(release, work: try makeTempHome())
        }
        #expect(await log.calls.count == 2)
    }

    @Test func installRefusesAnArchiveWithoutTheExpectedLayout() async throws {
        let log = CallLog()
        let runner = fakeGitHub(log, zip: Data("ok".utf8), sums: Self.honestSums, layout: false)
        await #expect(throws: UpdateError.self) {
            try await Updater(runner: runner, current: "0.1.0").install(UpdateRelease(tag: "v0.2.0", version: "0.2.0"), work: try makeTempHome())
        }
        #expect(await log.calls.map { ($0[0] as NSString).lastPathComponent } == ["curl", "curl", "ditto"])
    }
}
