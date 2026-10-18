import Foundation
import Synchronization
import Testing
@testable import MacCtlCore

/// In-memory preferences keyed by setting id. Records every write and reset in order.
actor FakeBackend: SettingBackend {
    enum Op: Sendable, Equatable {
        case write(String, Value)
        case reset(String)
    }

    private(set) var stored: [String: Value]
    private(set) var ops: [Op] = []

    init(stored: [String: Value] = [:]) {
        self.stored = stored
    }

    func read(_ setting: Setting) async throws -> Value? {
        stored[setting.id]
    }

    func write(_ value: Value, for setting: Setting) async throws {
        stored[setting.id] = value
        ops.append(.write(setting.id, value))
    }

    func reset(_ setting: Setting) async throws {
        stored[setting.id] = nil
        ops.append(.reset(setting.id))
    }
}

/// Records each batch of side effects it is asked to run.
actor FakeRestarter: Restarter {
    private(set) var calls: [Set<SideEffect>] = []

    func run(_ effects: Set<SideEffect>) async throws {
        calls.append(effects)
    }
}

/// Grants every permission except the denied ones.
struct FakeProbe: PermissionProbe {
    var denied: Set<Permission> = []

    func isGranted(_ permission: Permission) async -> Bool {
        !denied.contains(permission)
    }

    func settingsURL(for permission: Permission) -> String {
        "x-apple.systempreferences:test"
    }
}

/// Snapshots in memory; `list()` is newest first like the file store.
final class InMemorySnapshotStore: SnapshotStore {
    private let state = Mutex<[Snapshot]>([])

    var saved: [Snapshot] { state.withLock { $0 } }

    func save(_ snapshot: Snapshot) throws {
        state.withLock { $0.append(snapshot) }
    }

    func list() throws -> [Snapshot] {
        state.withLock { snapshots in
            snapshots.sorted { a, b in a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id > b.id }
        }
    }

    func load(id: String) throws -> Snapshot {
        let found = state.withLock { snapshots in snapshots.first(where: { $0.id == id }) }
        guard let snapshot = found else {
            throw MacCtlError.snapshotNotFound(id)
        }
        return snapshot
    }
}

/// A clock that advances one second per call, so snapshot ids differ.
final class TestClock: Sendable {
    private let seconds = Mutex<TimeInterval>(1_792_154_096)

    func next() -> Date {
        seconds.withLock { value in
            value += 1
            return Date(timeIntervalSince1970: value)
        }
    }
}

enum TestCatalog {
    static let automation = Permission.automation(bundleID: "com.apple.systemevents")

    static let settings: [Setting] = [
        Setting(
            id: "dock.autohide", summary: "Hide the Dock", type: .bool,
            backend: .defaults(domain: "com.apple.dock", key: "autohide", type: .bool),
            after: [.restart(process: "Dock")], systemDefault: .bool(false)),
        Setting(
            id: "dock.tilesize", summary: "Dock icon size", type: .int(min: 16, max: 128),
            backend: .defaults(domain: "com.apple.dock", key: "tilesize", type: .int),
            after: [.restart(process: "Dock")], systemDefault: .int(64)),
        Setting(
            id: "finder.show-extensions", summary: "Show file extensions", type: .bool,
            backend: .defaults(domain: Backend.globalDomain, key: "AppleShowAllExtensions", type: .bool),
            after: [.restart(process: "Finder")], systemDefault: .bool(false)),
        Setting(
            id: "keyboard.key-repeat", summary: "Key repeat interval", type: .int(min: 1, max: 120),
            backend: .defaults(domain: Backend.globalDomain, key: "KeyRepeat", type: .int),
            after: [.logout], systemDefault: .int(6)),
        Setting(
            id: "appearance.mode", summary: "Light or dark", type: .enumeration(["light", "dark"]),
            permissions: [automation],
            backend: .appleScript(get: "get", set: "set"), systemDefault: .string("light")),
        Setting(
            id: "system.hostname", summary: "Computer name", type: .string, risk: .admin,
            backend: .defaults(domain: "test", key: "hostname", type: .string)),
    ]
}

struct Harness {
    let engine: Engine
    let backend: FakeBackend
    let restarter: FakeRestarter
    let store: InMemorySnapshotStore

    init(stored: [String: Value] = [:], denied: Set<Permission> = []) {
        backend = FakeBackend(stored: stored)
        restarter = FakeRestarter()
        store = InMemorySnapshotStore()
        let clock = TestClock()
        engine = Engine(
            registry: Registry(TestCatalog.settings),
            backend: backend,
            restarter: restarter,
            probe: FakeProbe(denied: denied),
            snapshots: store,
            osVersion: { "26.0" },
            now: { clock.next() }
        )
    }
}

/// Expects `body` to throw a `MacCtlError` with this stable `code`.
func expectMacCtlError<T>(
    _ code: String, sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async throws -> T
) async {
    do {
        _ = try await body()
        Issue.record("Expected \(code), but nothing was thrown", sourceLocation: sourceLocation)
    } catch let error as MacCtlError {
        #expect(error.code == code, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Expected \(code), got \(error)", sourceLocation: sourceLocation)
    }
}
