# Persistence and secrets

Choose the smallest tier that fits (same ladder Glaze uses):

| Data | Tier |
|---|---|
| Small preferences (toggles, last tab, window size) | `@AppStorage` / `UserDefaults` |
| User content, history, caches you must not lose | Codable JSON in `Application Support/<bundle id>/`, atomic writes |
| Relational data, queries, thousands of rows | SwiftData (or SQLite) in the same directory |
| Tokens, passwords, API keys | Keychain (generic password) |
| Large files the user owns | Files the user picked (`fileImporter`), with security-scoped bookmarks if sandboxed |

## JSON store (verified: missing file → fallback, round trip, corrupt file → throws)

```swift
actor JSONStore<Value: Codable & Sendable> {
    private let url: URL
    private let fallback: Value

    init(file: String, bundleID: String, fallback: Value) {
        let dir = URL.applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory)
        url = dir.appending(path: file)
        self.fallback = fallback
    }

    /// Missing file -> fallback. Corrupt file -> throws (never silently overwrite user data).
    func load() throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return fallback
        }
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
```

`actor` serializes concurrent saves; `.atomic` writes a temp file and renames, so a crash never leaves
half a file.

## Keychain

```swift
enum Keychain {
    static func set(_ value: String, account: String, service: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIError(status: nil, message: "Keychain error \(status)") }
    }

    static func get(account: String, service: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
```

`service` = bundle id. Ad-hoc re-signing changes the code signature, so macOS may ask the user to allow
access again after a rebuild. That is expected in development.

## Verify

- Relaunch the app: state survives.
- Delete the file: app starts clean. Corrupt the file: app shows an error and does not overwrite it.
- `security find-generic-password -s <bundle id>` shows the item; the value is in no plist or log.
