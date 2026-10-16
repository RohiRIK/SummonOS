import ArgumentParser
import Foundation
import MacCtlCore

/// Options every command accepts.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Print one JSON object (default when stdout is not a terminal).")
    var json = false

    var useJSON: Bool { json || isatty(STDOUT_FILENO) == 0 }
}

/// `{"ok": true, "command": "...", "result": ...}`
struct SuccessEnvelope<R: Encodable>: Encodable {
    let ok: Bool
    let command: String
    let result: R
}

/// `{"ok": false, "command": "...", "error": {"code": "...", "message": "..."}}`
struct ErrorEnvelope: Encodable {
    struct Body: Encodable {
        let code: String
        let message: String
    }

    let ok: Bool
    let command: String
    let error: Body
}

enum Output {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Runs a command body and prints its result (JSON or text). Maps errors to exit codes.
    static func run<R: Encodable>(
        _ command: String,
        _ options: GlobalOptions,
        text: (R) -> String,
        _ body: () async throws -> R
    ) async throws {
        let json = options.useJSON
        do {
            let result = try await body()
            if json {
                try printJSON(SuccessEnvelope(ok: true, command: command, result: result))
            } else {
                let rendered = text(result)
                if !rendered.isEmpty { print(rendered) }
            }
        } catch let error as MacCtlError {
            report(command: command, code: error.code, message: error.description, json: json)
            throw ExitCode(error.exitCode)
        } catch let exit as ExitCode {
            throw exit
        } catch {
            report(command: command, code: "internal_error", message: String(describing: error), json: json)
            throw ExitCode.failure
        }
    }

    static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try makeEncoder().encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    static func report(command: String, code: String, message: String, json: Bool) {
        if json {
            let envelope = ErrorEnvelope(ok: false, command: command, error: .init(code: code, message: message))
            if let data = try? makeEncoder().encode(envelope) {
                print(String(decoding: data, as: UTF8.self))
                return
            }
        }
        writeStderr("macctl: \(message)\n")
    }

    static func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}

/// Profile files given to `diff` and `apply`.
enum ProfileLoader {
    static func load(_ path: String) throws -> Profile {
        let expanded = (path as NSString).expandingTildeInPath
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: expanded))
        } catch {
            throw MacCtlError.invalidProfile("cannot read \(path): \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(Profile.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw MacCtlError.invalidProfile("\(path): missing key \"\(key.stringValue)\"")
        } catch let DecodingError.typeMismatch(_, context) {
            throw MacCtlError.invalidProfile("\(path): \(context.debugDescription)")
        } catch let DecodingError.dataCorrupted(context) {
            throw MacCtlError.invalidProfile("\(path): \(context.debugDescription)")
        } catch {
            throw MacCtlError.invalidProfile("\(path): \(error.localizedDescription)")
        }
    }
}

// MARK: - Text formatting

enum Human {
    /// Left-aligned columns separated by two spaces; the last column is not padded.
    static func table(_ rows: [[String]]) -> String {
        guard let width = rows.map(\.count).max(), width > 0 else { return "" }
        var widths = Array(repeating: 0, count: width)
        for row in rows {
            for (i, cell) in row.enumerated() where i < width - 1 {
                widths[i] = max(widths[i], cell.count)
            }
        }
        return rows.map { row in
            row.enumerated().map { i, cell in
                i < row.count - 1 ? cell.padding(toLength: widths[i], withPad: " ", startingAt: 0) : cell
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    static func value(_ value: Value?) -> String {
        guard let value else { return "(unset)" }
        if case .string(let s) = value, s.isEmpty { return "\"\"" }
        return value.description
    }

    static func changes(_ changes: [Change]) -> String {
        table(changes.map { ["  " + $0.id, value($0.from), "->", value($0.to)] })
    }

    static func applied(_ result: ApplyResult) -> String { applyResult(result, verb: "Applied") }
    static func restored(_ result: ApplyResult) -> String { applyResult(result, verb: "Restored") }

    static func applyResult(_ result: ApplyResult, verb: String) -> String {
        var lines: [String] = []
        let n = result.changes.count
        let plural = n == 1 ? "change" : "changes"
        if n == 0 {
            lines.append("Nothing to change; already matches.")
        } else if result.dryRun {
            lines.append("Dry run: \(n) \(plural) would be made (nothing written).")
            lines.append(changes(result.changes))
        } else {
            lines.append("\(verb) \(n) \(plural).")
            lines.append(changes(result.changes))
        }
        if let id = result.snapshotID, !result.dryRun {
            lines.append("Snapshot \(id). Revert with: macctl undo \(id)")
        }
        for note in result.notes {
            lines.append("Note: \(note)")
        }
        return lines.joined(separator: "\n")
    }
}
