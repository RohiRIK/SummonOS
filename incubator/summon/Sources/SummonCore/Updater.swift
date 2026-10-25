import CryptoKit
import Foundation

/// `stable` follows the `vX.Y.Z` release tags; `edge` follows the rolling `edge` prerelease rebuilt from every green main.
public enum UpdateChannel: String, Sendable, Codable, CaseIterable {
    case stable
    case edge
}

/// The channel `summon update` uses when none is given: `~/.config/summon/defaults/channel` (default stable).
public struct UpdateChannelStore: Sendable {
    public let paths: SummonPaths
    public init(paths: SummonPaths) { self.paths = paths }
    public var file: URL { paths.config.appendingPathComponent("defaults/channel") }

    public func load() -> UpdateChannel {
        TextFile.firstLine(file).flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }

    public func save(_ channel: UpdateChannel) throws {
        try TextFile.write(channel.rawValue + "\n", to: file)
    }
}

/// A SemVer 2.0 version (`0.1.0`, `0.1.0-edge.abc1234`), compared by SemVer precedence.
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let core: [Int]
    public let prerelease: [String]
    public let description: String

    public init?(_ text: String) {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let pre = parts.count > 1 ? parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard parts.count == 1 || pre.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCIIDigit || $0.isASCIILetter || $0 == "-" } })
        else { return nil }
        core = numbers.compactMap { Int($0) }
        guard core.count == 3 else { return nil }
        prerelease = pre
        description = text
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.core != rhs.core { return lhs.core.lexicographicallyPrecedes(rhs.core) }
        // A prerelease sorts before its release: 0.1.0-edge.abc < 0.1.0.
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            switch (Int(a), Int(b)) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.core == rhs.core && lhs.prerelease == rhs.prerelease
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}

/// One downloadable SummonOS build: the release tag, the build's version and its two assets.
public struct UpdateRelease: Sendable, Equatable {
    public let tag: String
    public let version: String
    public var zipName: String { "summonos-\(version)-macos-universal.zip" }
    public var zipURL: String { "\(Updater.download)/\(tag)/\(zipName)" }
    public var sumsURL: String { "\(Updater.download)/\(tag)/SHA256SUMS" }
}

public struct UpdateCheck: Sendable, Equatable {
    public let channel: UpdateChannel
    public let current: String
    public let release: UpdateRelease
    public let available: Bool
}

public enum UpdateError: Error, Equatable, CustomStringConvertible {
    case noRelease(UpdateChannel)
    case unreadable(String)
    case checksumMismatch(String)
    case badArchive(String)

    public var description: String {
        switch self {
        case .noRelease(.stable): return "No SummonOS release is published yet."
        case .noRelease(.edge): return "No edge build is published yet."
        case .unreadable(let detail): return "Could not read the GitHub releases: \(detail)"
        case .checksumMismatch(let file): return "Checksum mismatch for \(file): refusing to install it."
        case .badArchive(let detail): return "The release archive does not have the expected layout: \(detail)"
        }
    }
}

/// `summon update`: finds the newest build on a channel, downloads it with curl (as install.sh does), verifies it
/// against SHA256SUMS, and hands it to the release's own staged installer (scripts/install.sh), which rolls back.
public struct Updater: Sendable {
    public static let api = "https://api.github.com/repos/RohiRIK/SummonOS"
    public static let download = "https://github.com/RohiRIK/SummonOS/releases/download"

    public let runner: Runner
    public let current: String
    public let curl: String
    public let ditto: String

    public init(runner: @escaping Runner, current: String = SummonVersion.current,
                curl: String = "/usr/bin/curl", ditto: String = "/usr/bin/ditto") {
        self.runner = runner
        self.current = current
        self.curl = curl
        self.ditto = ditto
    }

    struct APIRelease: Decodable {
        struct Asset: Decodable { let name: String }
        let tag_name: String
        let draft: Bool?
        let assets: [Asset]?
    }

    /// stable: the highest `vX.Y.Z` tag (prereleases count: every release is a preview for now), never `edge`.
    /// edge: the `edge` release, whose version is in its zip name (`summonos-0.1.0-edge.abc1234-macos-universal.zip`).
    public static func pick(_ json: Data, channel: UpdateChannel) throws -> UpdateRelease {
        let releases: [APIRelease]
        do { releases = try JSONDecoder().decode([APIRelease].self, from: json) }
        catch { throw UpdateError.unreadable(String(describing: error)) }
        let published = releases.filter { $0.draft != true }
        switch channel {
        case .stable:
            let tagged = published.compactMap { release -> (ReleaseVersion, String)? in
                guard release.tag_name.hasPrefix("v"), let version = ReleaseVersion(String(release.tag_name.dropFirst())) else { return nil }
                return (version, release.tag_name)
            }
            guard let best = tagged.max(by: { $0.0 < $1.0 }) else { throw UpdateError.noRelease(.stable) }
            return UpdateRelease(tag: best.1, version: best.0.description)
        case .edge:
            let prefix = "summonos-", suffix = "-macos-universal.zip"
            guard let edge = published.first(where: { $0.tag_name == "edge" }),
                  let name = edge.assets?.map(\.name).first(where: { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }),
                  let version = ReleaseVersion(String(name.dropFirst(prefix.count).dropLast(suffix.count)))
            else { throw UpdateError.noRelease(.edge) }
            return UpdateRelease(tag: "edge", version: version.description)
        }
    }

    /// stable updates only to a newer version; edge installs whatever build it points at when it differs from this one.
    public static func isAvailable(current: String, latest: String, channel: UpdateChannel) -> Bool {
        guard let new = ReleaseVersion(latest) else { return false }
        guard let old = ReleaseVersion(current) else { return true }
        return channel == .edge ? new != old : old < new
    }

    public func check(_ channel: UpdateChannel) async throws -> UpdateCheck {
        let output: String
        do { output = try await runner(curl, ["-fsSL", "--retry", "3", "\(Self.api)/releases?per_page=30"]) }
        catch { throw UpdateError.unreadable("GitHub is unreachable or rate limited (\(error))") }
        let release = try Self.pick(Data(output.utf8), channel: channel)
        return UpdateCheck(channel: channel, current: current, release: release,
                           available: Self.isAvailable(current: current, latest: release.version, channel: channel))
    }

    /// The digest SHA256SUMS lists for `file` (`<hex>  <name>`, or `<hex> *<name>` in binary mode).
    public static func expectedDigest(_ sums: String, file: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 2, fields[0].count == 64, fields[0].allSatisfy(\.isHexDigit) else { continue }
            let name = fields[1].hasPrefix("*") ? String(fields[1].dropFirst()) : fields[1]
            if name == file { return fields[0].lowercased() }
        }
        return nil
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Throws unless `zip` matches its SHA256SUMS line; a missing line is a mismatch too.
    public static func verify(_ zip: URL, sums: String) throws {
        guard let expected = expectedDigest(sums, file: zip.lastPathComponent), try sha256(of: zip) == expected else {
            throw UpdateError.checksumMismatch(zip.lastPathComponent)
        }
    }

    /// Downloads and verifies the release into `work` (an empty temp folder), unpacks it and runs its installer.
    /// Returns the installer's output. Nothing is replaced before the checksum and the layout pass.
    public func install(_ release: UpdateRelease, work: URL) async throws -> String {
        let zip = work.appendingPathComponent(release.zipName)
        let sums = work.appendingPathComponent("SHA256SUMS")
        _ = try await runner(curl, ["-fsSL", "--retry", "3", "-o", zip.path, release.zipURL])
        _ = try await runner(curl, ["-fsSL", "--retry", "3", "-o", sums.path, release.sumsURL])
        try Self.verify(zip, sums: TextFile.read(sums) ?? "")
        let unpacked = work.appendingPathComponent("unpacked")
        _ = try await runner(ditto, ["-x", "-k", zip.path, unpacked.path])
        let package = unpacked.appendingPathComponent("summonos-\(release.version)")
        let app = package.appendingPathComponent("Summon.app"), macctl = package.appendingPathComponent("bin/macctl")
        let script = package.appendingPathComponent("scripts/install.sh")
        let files = FileManager.default
        guard files.fileExists(atPath: app.path), files.isExecutableFile(atPath: macctl.path), files.fileExists(atPath: script.path) else {
            throw UpdateError.badArchive("summonos-\(release.version)/{Summon.app, bin/macctl, scripts/install.sh}")
        }
        // The same hand-off as the top-level install.sh: the staged installer swaps both in and rolls back on failure.
        return try await runner("/usr/bin/env", ["SUMMONOS_APP_SOURCE=\(app.path)", "SUMMONOS_MACCTL_SOURCE=\(macctl.path)",
                                                 "/bin/bash", script.path])
    }
}
