# Talking to backends (HTTP APIs)

Snippets are type-checked under Swift 6 (macOS 14).

## Rules (from Glaze's external-API skill, adapted to Swift)

1. **curl the endpoint first.** Confirm shape, auth, and error bodies before writing Swift.
2. **Service in Core, not in views.** One `APIClient` per backend; feature methods on top.
3. **Transform at the boundary.** Decode a `…DTO`, map to a domain type. Views never see raw JSON.
4. **Specific errors.** Carry the HTTP status; map 401 to "Sign in again", 429 to "Try again in N s".
5. **Nothing hardcoded.** Base URL, IDs, and account names come from settings; tokens from the Keychain.
6. **Return only what the UI needs.** Smaller models, fewer re-renders.
7. **Third-party calls are visible.** Name the service in the UI; call only on user action when the
   request reveals something about the user (public IP, location).

## APIClient

```swift
struct APIError: LocalizedError {
    let status: Int?
    let message: String
    var errorDescription: String? { status.map { "\(message) (HTTP \($0))" } ?? message }
}

struct APIClient: Sendable {
    let base: URL
    var token: @Sendable () async throws -> String?
    var session: URLSession = .shared

    func get<T: Decodable & Sendable>(_ path: String, as: T.Type = T.self) async throws -> T {
        var request = URLRequest(url: base.appending(path: path), timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try await token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: nil, message: "No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: http.statusCode == 401 ? "Sign in again" : "Request failed")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

struct IssueDTO: Decodable, Sendable { let id: Int; let title: String; let state: String }
struct Issue: Identifiable, Sendable { let id: Int; let title: String; let isOpen: Bool }
extension Issue { init(_ dto: IssueDTO) { self.init(id: dto.id, title: dto.title, isOpen: dto.state == "open") } }
```

Test it with a `URLProtocol` stub or by injecting a `session` configured with one; test the DTO
mapping as pure functions with captured JSON fixtures.

## Auth

- **API key / personal token:** Settings window field, saved to the Keychain (`Data.md`), read via the
  `token` closure. Show "Connected as …" after a successful test call.
- **OAuth 2.0:** `ASWebAuthenticationSession` with PKCE and a custom URL scheme callback
  (`CFBundleURLTypes` in Info.plist). Store access + refresh tokens in the Keychain; refresh on 401 once,
  then ask the user to sign in again. Never embed a client secret in the app.
- **Local CLI that already has auth** (e.g. `gh`, `claude`): call it with `Process` (`System.md`) instead
  of re-implementing auth, but only when the user already uses that tool.

## Live data

- Poll only while the surface is visible; back off on errors (double the interval up to a cap).
- Prefer push if the backend offers it: `URLSessionWebSocketTask`, server-sent events via
  `session.bytes(for:)` + `for try await line in bytes.lines`.
- Keep the last good value on screen, dimmed, while refreshing or after an error. Never blank the UI.

## Offline

- Check reachability by trying; do not pre-check with `NWPathMonitor` and skip the call.
- `NWPathMonitor` is for showing an offline badge and for retrying when the path comes back.
