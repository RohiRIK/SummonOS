import Foundation
import Testing
@testable import MacCtlCore

struct ValueParsingTests {
    @Test(arguments: ["true", "yes", "on", "1", "TRUE", " Yes "])
    func boolTrueSpellings(_ text: String) throws {
        #expect(try ValueType.bool.parse(text, id: "x") == .bool(true))
    }

    @Test(arguments: ["false", "no", "off", "0", "False"])
    func boolFalseSpellings(_ text: String) throws {
        #expect(try ValueType.bool.parse(text, id: "x") == .bool(false))
    }

    @Test func boolRejectsOtherText() async {
        await expectMacCtlError("invalid_value") { try ValueType.bool.parse("maybe", id: "dock.autohide") }
    }

    @Test func intRange() async throws {
        let type = ValueType.int(min: 16, max: 128)
        #expect(try type.parse("40", id: "dock.tilesize") == .int(40))
        #expect(try type.parse("16", id: "dock.tilesize") == .int(16))
        await expectMacCtlError("invalid_value") { try type.parse("200", id: "dock.tilesize") }
        await expectMacCtlError("invalid_value") { try type.parse("4.5", id: "dock.tilesize") }
        #expect(type.validate(.int(8)) == "must be between 16 and 128")
        #expect(ValueType.int(min: 1, max: nil).validate(.int(0)) == "must be at least 1")
    }

    @Test func invalidValueCarriesIDAndText() async {
        do {
            _ = try ValueType.int(min: 0, max: 10).parse("11", id: "a.b")
            Issue.record("expected a throw")
        } catch let error as MacCtlError {
            #expect(error == .invalidValue(id: "a.b", value: "11", reason: "must be between 0 and 10"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func doubleCoercesInt() throws {
        let type = ValueType.double(min: 0, max: 1)
        #expect(try type.parse("1", id: "x") == .double(1))
        #expect(try type.parse("0.25", id: "x") == .double(0.25))
        #expect(try type.coerce(.int(0), id: "x") == .double(0))
        #expect(type.validate(.double(1.5)) == "must be between 0.0 and 1.0")
        #expect(type.validate(.double(.nan)) != nil)
    }

    @Test func enumerationIsExact() async throws {
        let type = ValueType.enumeration(["light", "dark"])
        #expect(try type.parse("dark", id: "appearance.mode") == .string("dark"))
        await expectMacCtlError("invalid_value") { try type.parse("Dark", id: "appearance.mode") }
        #expect(type.validate(.string("blue")) == "must be one of: light, dark")
    }

    @Test func pathExpandsTilde() async throws {
        let home = NSString(string: "~").expandingTildeInPath
        #expect(try ValueType.path.parse("~/Pictures/Shots", id: "x") == .string(home + "/Pictures/Shots"))
        #expect(try ValueType.path.parse("/tmp/a", id: "x") == .string("/tmp/a"))
        await expectMacCtlError("invalid_value") { try ValueType.path.parse("relative/dir", id: "x") }
    }

    @Test func wrongKindIsRejected() async {
        #expect(ValueType.bool.validate(.int(1)) == "expected a boolean, got an integer")
        #expect(ValueType.string.validate(.bool(true)) != nil)
        await expectMacCtlError("invalid_value") { try ValueType.int(min: nil, max: nil).coerce(.string("4"), id: "x") }
    }

    @Test func stringKeepsText() throws {
        #expect(try ValueType.string.parse(" My Mac ", id: "x") == .string(" My Mac "))
    }
}

struct RegistryTests {
    @Test func looksUpAndGroups() async throws {
        let registry = Registry(TestCatalog.settings)
        #expect(registry.all.count == TestCatalog.settings.count)
        #expect(try registry.setting("dock.autohide").id == "dock.autohide")
        #expect(registry.byDomain["dock"]?.map(\.id) == ["dock.autohide", "dock.tilesize"])
        #expect(registry.domains.first == "appearance")
        await expectMacCtlError("unknown_setting") { try registry.setting("dock.nope") }
    }
}
