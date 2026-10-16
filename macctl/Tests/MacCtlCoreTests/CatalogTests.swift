import Foundation
import Testing
@testable import MacCtlCore

@Suite("Catalog")
struct CatalogTests {
    @Test func idsAreUnique() {
        let ids = Catalog.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids: \(ids)")
    }

    @Test func catalogHasAboutFifteenSettings() {
        #expect(Catalog.all.count >= 15)
    }

    @Test(arguments: Catalog.all.map(\.id))
    func idMatchesPattern(_ id: String) {
        #expect(id.wholeMatch(of: #/[a-z]+\.[a-z0-9-]+/#) != nil)
    }

    @Test(arguments: Catalog.all)
    func summaryIsOneLine(_ setting: Setting) {
        #expect(!setting.summary.isEmpty)
        #expect(!setting.summary.contains("\n"))
    }

    @Test(arguments: Catalog.all)
    func systemDefaultMatchesType(_ setting: Setting) {
        guard let value = setting.systemDefault else { return }
        #expect(Self.isValid(value, for: setting.type), "\(setting.id): \(value) is not a valid \(setting.type)")
    }

    @Test(arguments: Catalog.all)
    func defaultsTypeAgreesWithValueType(_ setting: Setting) {
        guard case .defaults(_, _, let stored) = setting.backend else { return }
        let ok: Bool = switch (setting.type, stored) {
        case (.bool, .bool): true
        case (.int, .int): true
        case (.double, .float): true
        case (.string, .string), (.enumeration, .string), (.path, .string): true
        default: false
        }
        #expect(ok, "\(setting.id): \(setting.type) stored as -\(stored.rawValue)")
    }

    @Test(arguments: Catalog.all)
    func enumerationsAreNonEmptyAndUnique(_ setting: Setting) {
        guard case .enumeration(let options) = setting.type else { return }
        #expect(!options.isEmpty)
        #expect(Set(options).count == options.count)
    }

    @Test func darkModeUsesSystemEventsWithArgv() {
        let setting = Catalog.all.first { $0.id == "appearance.dark-mode" }
        #expect(setting?.permissions == [.automation(bundleID: "com.apple.systemevents")])
        guard case .appleScript(_, let set)? = setting?.backend else {
            Issue.record("appearance.dark-mode should use the AppleScript backend")
            return
        }
        #expect(set.contains("on run argv"))
        #expect(set.contains("item 1 of argv"))
    }

    @Test func defaultProfileDecodesAndUsesCatalogIDs() throws {
        let data = try Data(contentsOf: Self.defaultProfileURL)
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        #expect(profile.name == "default")
        #expect(profile.version == 1)
        #expect(!profile.settings.isEmpty)

        let byID = Dictionary(uniqueKeysWithValues: Catalog.all.map { ($0.id, $0) })
        for (id, value) in profile.settings {
            guard let setting = byID[id] else {
                Issue.record("profile references unknown id \(id)")
                continue
            }
            #expect(Self.isValid(value, for: setting.type), "\(id): \(value) is not a valid \(setting.type)")
        }
    }

    // MARK: Helpers

    /// `macctl/profiles/default.json`, found from this file's location.
    static var defaultProfileURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MacCtlCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // macctl
            .appendingPathComponent("profiles/default.json")
    }

    /// Local validation so these tests do not depend on the value-parsing module.
    static func isValid(_ value: Value, for type: ValueType) -> Bool {
        switch (type, value) {
        case (.bool, .bool):
            return true
        case (.int(let lo, let hi), .int(let i)):
            return (lo.map { i >= $0 } ?? true) && (hi.map { i <= $0 } ?? true)
        case (.double(let lo, let hi), .double(let d)):
            return (lo.map { d >= $0 } ?? true) && (hi.map { d <= $0 } ?? true)
        case (.double(let lo, let hi), .int(let i)):
            let d = Double(i)
            return (lo.map { d >= $0 } ?? true) && (hi.map { d <= $0 } ?? true)
        case (.string, .string):
            return true
        case (.enumeration(let options), .string(let s)):
            return options.contains(s)
        case (.path, .string(let s)):
            return s.hasPrefix("/") || s.hasPrefix("~")
        default:
            return false
        }
    }
}
