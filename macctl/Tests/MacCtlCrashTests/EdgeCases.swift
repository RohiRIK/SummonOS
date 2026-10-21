import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Plan v3 §1.5 edge cases (and the R-g check), driven through the CLI like the matrix.
/// Each returns its failures; fake-only cases are skipped (and reported) on cfprefs.
struct Edge: Sendable {
    let name: String
    var fakeOnly = false
    var needsNonRoot = false
    var needsForeignOwner = false
    let run: @Sendable (World) throws -> [String]
}

/// Gives a file to `nobody`: chown(2) as root, else `sudo -n chown` when `MACCTL_CRASH_SUDO=1`
/// (the CI runner). Only ever a file inside this case's temp root.
func chownToNobody(_ url: URL) -> Bool {
    precondition(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    if geteuid() == 0 { return chown(url.path, 65534, 65534) == 0 || chown(url.path, uid_t(bitPattern: -2), gid_t(bitPattern: -2)) == 0 }
    guard canChownToNobody else { return false }
    return spawn("/usr/bin/sudo", ["-n", "/usr/sbin/chown", "nobody", url.path], environment: ["PATH": "/usr/bin:/bin:/usr/sbin"],
                 in: FileManager.default.temporaryDirectory).ok
}

var canChownToNobody: Bool { geteuid() == 0 || Config.environment["MACCTL_CRASH_SUDO"] == "1" }

enum Edges {
    static let o1 = Ops.all.first { $0.name == "O1" }!.specs
    static let o2 = Ops.o2Specs

    static func journalFile(_ w: World) -> URL? {
        w.journalNames().first.map { w.journal.appendingPathComponent($0) }
    }

    static func crashO2(_ w: World, at point: String) throws -> (pre: [String: String], id: String) {
        let command = try Ops.seedO2(w)
        let pre = w.state()
        let run = w.macctl(command, failpoint: point)
        guard run.killed, let id = w.headerIDs().first else { throw HarnessError("crash at \(point): \(run.summary)") }
        return (pre, id)
    }

    static func expectPre(_ w: World, _ pre: [String: String], _ what: String) -> [String] {
        w.state() == pre ? [] : ["\(what): not at pre: \(describeDiff(pre, w.state()))"]
    }

    static func torn(_ point: String, cut: @escaping @Sendable (Data) -> Data) -> @Sendable (World) throws -> [String] {
        { w in
            let (pre, _) = try crashO2(w, at: point)
            guard let file = journalFile(w) else { return ["no journal"] }
            try cut(try Data(contentsOf: file)).write(to: file)
            let headers = w.headerPrints()
            let run = w.macctl(["recover"])
            return (run.ok ? [] : ["recover: \(run.summary)"]) + expectPre(w, pre, "after recover") + invariants(w, headers: headers)
        }
    }

    /// Drops the last line's second half (and its newline).
    static func cutLastLine(_ data: Data) -> Data {
        var lines = data.split(separator: 0x0a).map { Data($0) }
        let last = lines.removeLast()
        return lines.reduce(into: Data()) { $0 += $1 + Data([0x0a]) } + last.prefix(last.count / 2)
    }

    static let all: [Edge] = [
        Edge(name: "E-torn intent (I2.2, last line cut mid-JSON)", run: torn("I2.2@1", cut: cutLastLine)),
        Edge(name: "E-torn applied (A2.2, last line cut mid-JSON)", run: torn("A2.2@1", cut: cutLastLine)),
        Edge(name: "E-torn no trailing newline (A2.2)", run: torn("A2.2@1") { Data($0.dropLast()) }),

        Edge(name: "E-corrupt middle line") { w in
            let (_, id) = try crashO2(w, at: "A2.2@1")
            guard let file = journalFile(w) else { return ["no journal"] }
            var lines = String(decoding: try Data(contentsOf: file), as: UTF8.self).split(separator: "\n").map(String.init)
            lines[1] = "{garbage"
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
            let before = w.state()
            let run = w.macctl(["recover"])
            var failures = run.errorCode == "journal_corrupt" ? [] : ["expected journal_corrupt, got \(run.summary)"]
            if w.state() != before { failures.append("a corrupt journal must not write anything") }
            let blocked = w.macctl(["set", "t.c", "z"])
            if blocked.errorCode != "recovery_pending" { failures.append("apply next to a corrupt journal: \(blocked.summary)") }
            let abandon = w.macctl(["recover", "--abandon", id])
            if !abandon.ok { failures.append("recover --abandon: \(abandon.summary)") }
            if !FileManager.default.fileExists(atPath: file.path + ".corrupt") { failures.append("abandoned journal not kept as .corrupt") }
            return failures
        },
        Edge(name: "E-corrupt with an intact unresolved session alongside (R-c)") { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            try Ops.twoUnresolvedSessions(w, firstCommand: ["set", "t.a", "true"], secondCommand: ["set", "t.b", "x"])
            let names = w.journalNames()
            guard names.count == 2 else { return ["fixture: \(names)"] }
            let older = w.journal.appendingPathComponent(names[0])
            var lines = String(decoding: try Data(contentsOf: older), as: UTF8.self).split(separator: "\n").map(String.init)
            lines.insert("{garbage", at: 1)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: older)
            let run = w.macctl(["recover"])
            var failures = run.errorCode == "journal_corrupt" ? [] : ["expected journal_corrupt, got \(run.summary)"]
            let now = w.state()
            for key in Set(pre.keys).union(now.keys) where key.contains("B") && pre[key] != now[key] {
                failures.append("the intact session was not recovered: \(key)")
            }
            if w.value(w.a, "A") == nil { failures.append("the corrupt session must stay unrecovered (t.a still set)") }
            return failures
        },

        Edge(name: "E-gate apply after a crash is recovery_pending, allowed after recover") { w in
            try w.seed(w.a, "A", .bool(false))
            _ = w.macctl(["set", "t.a", "true"], failpoint: "A1.2")
            let blocked = w.macctl(["set", "t.a", "false"])
            var failures = blocked.errorCode == "recovery_pending" ? [] : ["apply: \(blocked.summary)"]
            _ = w.macctl(["recover"])
            let allowed = w.macctl(["set", "t.a", "true"])
            if !allowed.ok { failures.append("apply after recover: \(allowed.summary)") }
            return failures
        },
        Edge(name: "E-gate undo after a crash is recovery_pending") { w in
            try w.seed(w.a, "A", .bool(false))
            _ = w.macctl(["set", "t.a", "true"], failpoint: "A1.2")
            let blocked = w.macctl(["undo"])
            return blocked.errorCode == "recovery_pending" ? [] : ["undo: \(blocked.summary)"]
        },

        Edge(name: "E-hand edit key 2 after A2.2, crash at E1: flagged, the rest at pre") { w in
            let (pre, _) = try crashO2(w, at: "E1@1")
            try w.seed(w.b, "C", .string("hand"))
            let run = w.macctl(["recover"])
            var failures = run.errorCode == "partial_restore" ? [] : ["expected partial_restore, got \(run.summary)"]
            if w.value(w.b, "C") != "hand" { failures.append("hand edit was overwritten: \(w.value(w.b, "C") ?? "nil")") }
            try w.seed(w.b, "C", nil)  // waive the flagged key; everything else must be pre
            return failures + expectPre(w, pre, "keys 1 and 3")
        },
        Edge(name: "E-hand with recover --force restores everything") { w in
            let (pre, _) = try crashO2(w, at: "K2@1")
            try w.seed(w.b, "C", .string("hand"))
            let run = w.macctl(["recover", "--force"])
            return (run.ok ? [] : ["recover --force: \(run.summary)"]) + expectPre(w, pre, "after --force")
        },

        Edge(name: "E-forced managed key", fakeOnly: true) { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            try w.knob(".managed.plist", ["\(w.a)/A": true])
            let run = w.macctl(["set", "t.a", "true"])
            var failures = run.errorCode == "managed_setting" ? [] : ["expected managed_setting, got \(run.summary)"]
            if !w.headerIDs().isEmpty || !w.journalNames().isEmpty { failures.append("a header or journal was written") }
            return failures + expectPre(w, pre, "managed")
        },

        Edge(name: "E-perm journal dir unwritable refuses before the first write") { w in
            // macctl owns journal/ and resets its mode to 0700, so a 0500 dir is repaired, not refused.
            // An unwritable journal is simulated by a regular file where the directory must be.
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            FileManager.default.createFile(atPath: w.journal.path, contents: Data("in the way".utf8))
            let run = w.macctl(["set", "t.a", "true"])
            var failures = run.ok ? ["apply succeeded without a journal"] : []
            failures += expectPre(w, pre, "no journal")
            try FileManager.default.removeItem(at: w.journal)
            let recovered = w.macctl(["recover"])
            if !recovered.ok { failures.append("recover after removing it: \(recovered.summary)") }
            let applied = w.macctl(["set", "t.a", "true"])
            if !applied.ok { failures.append("apply after recover: \(applied.summary)") }
            return failures
        },
        Edge(name: "E-perm journal 0400 refuses recover before any write", needsNonRoot: true) { w in
            let (pre, _) = try crashO2(w, at: "A2.2@1")
            guard let file = journalFile(w) else { return ["no journal"] }
            let crashed = w.state()
            chmod(file.path, 0o400)
            let run = w.macctl(["recover"])
            var failures = run.ok ? ["recover succeeded with a read-only journal"] : []
            if w.state() != crashed { failures.append("recover wrote preferences without a writable journal") }
            chmod(file.path, 0o600)
            let recovered = w.macctl(["recover"])
            if !recovered.ok { failures.append("recover after fixing the mode: \(recovered.summary)") }
            return failures + expectPre(w, pre, "after recover")
        },

        Edge(name: "E-legacy pre-journal snapshot: listed, recover ignores it, undo works, never rewritten") { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            let applied = w.macctl(["set", "t.a", "true"])
            guard applied.ok, let id = w.headerIDs().first, let journal = journalFile(w) else { return ["setup: \(applied.summary)"] }
            try FileManager.default.removeItem(at: journal)
            let header = w.snapshots.appendingPathComponent("\(id).json")
            var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: header)) as? [String: Any])
            object["status"] = "completed"
            try FileManager.default.removeItem(at: header)
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]).write(to: header)
            chmod(header.path, 0o600)
            let legacy = try Data(contentsOf: header)
            var failures: [String] = []
            if w.statuses()[id] != "completed" { failures.append("legacy snapshot not listed as completed: \(w.statuses())") }
            let recovered = w.macctl(["recover"])
            if !recovered.ok || !w.journalNames().isEmpty { failures.append("recover touched the legacy snapshot: \(recovered.summary)") }
            let undo = w.macctl(["undo", id])
            if !undo.ok { failures.append("legacy undo: \(undo.summary)") }
            if (try? Data(contentsOf: header)) != legacy { failures.append("legacy header rewritten") }
            return failures + expectPre(w, pre, "after legacy undo")
        },

        Edge(name: "E-sensitive: no plaintext in the journal") { w in
            let specs = [Spec(id: "t.s", type: "string", key: "S", storage: "string", sensitive: true)]
            let s = try World(backend: w.backend, specs: specs)
            defer { s.cleanup() }
            try s.seed(s.a, "S", .string("old-secret-41"))
            let run = s.macctl(["set", "t.s", "new-secret-42"], failpoint: "A1.2")
            var failures = run.killed ? [] : ["did not crash: \(run.summary)"]
            let text = s.journalBytes().values.map { String(decoding: $0, as: UTF8.self) }.joined()
            if text.isEmpty { failures.append("no journal") }
            for secret in ["old-secret-41", "new-secret-42"] where text.contains(secret) {
                failures.append("journal contains plaintext \(secret)")
            }
            // The prior is a hash only, so recover cannot restore it: flagged, not guessed (ADR Q2).
            let recovered = s.macctl(["recover"])
            if recovered.errorCode != "partial_restore" { failures.append("expected partial_restore, got \(recovered.summary)") }
            let after = s.journalBytes().values.map { String(decoding: $0, as: UTF8.self) }.joined()
            if after.contains("old-secret-41") || after.contains("new-secret-42") { failures.append("recover journaled plaintext") }
            return failures
        },

        Edge(name: "E-rollback-nocrash (O6a without a crash)", fakeOnly: true) { w in
            let command = try Ops.seedO2(w)
            try w.knob(".fail-writes.plist", ["\(w.b)/C"])
            let pre = w.state()
            let run = w.macctl(command)
            var failures = run.errorCode == "mutation_failed" ? [] : ["expected mutation_failed, got \(run.summary)"]
            let last = w.journalLines().values.first?.last??["outcome"] as? String
            if last != "rolled_back" { failures.append("last line outcome \(last ?? "nil"), not rolled_back") }
            return failures + expectPre(w, pre, "rolled back") + invariants(w, headers: w.headerPrints())
        },

        Edge(name: "E-undo-ops: undo writes only revert lines in the same journal") { w in
            let command = try Ops.seedO2(w)
            let pre = w.state()
            guard w.macctl(command).ok, let id = w.headerIDs().first else { return ["setup apply failed"] }
            let headers = w.headerPrints()
            let names = w.journalNames()
            let before = w.journalLines().values.first?.count ?? 0
            let undo = w.macctl(["undo", id])
            var failures = undo.ok ? [] : ["undo: \(undo.summary)"]
            if w.journalNames() != names { failures.append("undo created a journal: \(w.journalNames())") }
            let ops = Set((w.journalLines().values.first ?? []).dropFirst(before).compactMap { $0?["op"] as? String })
            if !ops.isSubset(of: ["revert_intent", "reverted", "revert_flagged", "session_end"]) { failures.append("undo ops \(ops.sorted())") }
            return failures + expectPre(w, pre, "after undo") + invariants(w, headers: headers)
        },

        Edge(name: "E-mismatch: read-back returns a third value at change 2", fakeOnly: true) { w in
            let command = try Ops.seedO2(w)
            try w.knob(".read-back.plist", ["\(w.b)/C": "third"])
            let pre = w.state()
            let run = w.macctl(command)
            // Open decision: the rollback marks the third value revert_flagged (never overwritten).
            var failures = ["mutation_failed", "partial_restore"].contains(run.errorCode ?? "") ? [] : ["got \(run.summary)"]
            if w.value(w.b, "C") != "third" { failures.append("third value overwritten: \(w.value(w.b, "C") ?? "nil")") }
            let ops = (w.journalLines().values.first ?? []).compactMap { $0?["op"] as? String }
            if !ops.contains("revert_flagged") && !ops.contains("flagged") { failures.append("third value not flagged: \(ops)") }
            try w.seed(w.b, "C", nil)
            return failures + expectPre(w, pre, "keys 1 and 3")
        },

        Edge(name: "E-restore-drop: a restore that does not take is revert_flagged", fakeOnly: true) { w in
            // After the K2 crash, the next write to t.b's key is recover's restore; drop it.
            _ = try crashO2(w, at: "K2@1")
            try w.knob(".drop-writes.plist", ["\(w.b)/C"])
            let run = w.macctl(["recover"])
            var failures = run.errorCode == "partial_restore" ? [] : ["expected partial_restore, got \(run.summary)"]
            if w.value(w.b, "C") != "x" { failures.append("dropped restore: value \(w.value(w.b, "C") ?? "nil")") }
            let lines = w.journalLines().values.first ?? []
            let flagged = lines.compactMap { $0 }.filter { $0["op"] as? String == "revert_flagged" }
            if flagged.first?["reason"] as? String != "restore did not take" { failures.append("no revert_flagged{restore did not take}: \(flagged)") }
            if !w.statuses().filter({ $0.value == "pending" }).isEmpty { failures.append("session still pending") }
            let again = w.macctl(["recover"])
            if !again.ok { failures.append("second recover: \(again.summary)") }
            return failures
        },
        Edge(name: "R-g recover removes a stale .snapshot-*.tmp") { w in
            try FileManager.default.createDirectory(at: w.snapshots, withIntermediateDirectories: true)
            let stale = w.snapshots.appendingPathComponent(".snapshot-DEAD.tmp")
            FileManager.default.createFile(atPath: stale.path, contents: Data("x".utf8))
            let run = w.macctl(["recover"])
            return (run.ok ? [] : ["recover: \(run.summary)"]) + (FileManager.default.fileExists(atPath: stale.path) ? ["stale temp kept"] : [])
        },
        Edge(name: "R-g the next apply removes a stale .snapshot-*.tmp") { w in
            try w.seed(w.a, "A", .bool(false))
            try FileManager.default.createDirectory(at: w.snapshots, withIntermediateDirectories: true)
            let stale = w.snapshots.appendingPathComponent(".snapshot-DEAD.tmp")
            FileManager.default.createFile(atPath: stale.path, contents: Data("x".utf8))
            let run = w.macctl(["set", "t.a", "true"])
            return (run.ok ? [] : ["apply: \(run.summary)"]) + (FileManager.default.fileExists(atPath: stale.path) ? ["stale temp kept"] : [])
        },

        Edge(name: "E-lock holder killed at W2.2: the next process acquires at once") { w in
            let (pre, _) = try crashO2(w, at: "W2.2@1")
            let start = Date()
            let run = w.macctl(["recover"])
            let elapsed = Date().timeIntervalSince(start)
            var failures = run.ok ? [] : ["recover: \(run.summary)"]
            if elapsed > 5 { failures.append("recover took \(elapsed)s; a dead holder's flock must be free") }
            return failures + expectPre(w, pre, "after recover")
        },
        Edge(name: "E-lock a symlinked lock file is refused") { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            try FileManager.default.createDirectory(at: w.snapshots, withIntermediateDirectories: true)
            let target = w.root.appendingPathComponent("elsewhere")
            FileManager.default.createFile(atPath: target.path, contents: Data("keep".utf8))
            try FileManager.default.createSymbolicLink(at: w.snapshots.appendingPathComponent(".transaction.lock"), withDestinationURL: target)
            let run = w.macctl(["set", "t.a", "true"])
            var failures = run.ok ? ["apply took a symlinked lock"] : []
            if (try? Data(contentsOf: target)) != Data("keep".utf8) { failures.append("symlink target changed") }
            return failures + expectPre(w, pre, "symlinked lock")
        },
        Edge(name: "E-lock transaction_busy after 30 s while another process holds the lock") { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            let lock = try holdLock(w)
            defer { close(lock) }
            let start = Date()
            let run = w.macctl(["set", "t.a", "true"])
            let elapsed = Date().timeIntervalSince(start)
            var failures: [String] = []
            if run.ok || !run.summary.contains("transaction_busy") { failures.append("expected transaction_busy: \(run.summary)") }
            if elapsed < 29 { failures.append("gave up after \(elapsed)s; it must wait 30 s") }
            if elapsed > 60 { failures.append("waited \(elapsed)s; it must give up after 30 s") }
            let journals = (try? FileManager.default.contentsOfDirectory(atPath: w.journal.path))?.filter { $0.hasSuffix(".jsonl") } ?? []
            if !journals.isEmpty { failures.append("a busy apply wrote a journal: \(journals)") }
            return failures + expectPre(w, pre, "busy")
        },
        Edge(name: "E-lock get and --dry-run do not wait for a running apply") { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            let lock = try holdLock(w)
            defer { close(lock) }
            var failures: [String] = []
            for arguments in [["get", "t.a"], ["set", "t.a", "true", "--dry-run"]] {
                let start = Date()
                let run = w.macctl(arguments)
                let elapsed = Date().timeIntervalSince(start)
                if !run.ok { failures.append("\(arguments.joined(separator: " ")): \(run.summary)") }
                if elapsed > 5 { failures.append("\(arguments.joined(separator: " ")) waited \(elapsed)s for the lock") }
            }
            return failures + expectPre(w, pre, "read-only during apply")
        },
        Edge(name: "E-lock a lock file owned by another user is refused", needsForeignOwner: true) { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            let lock = w.snapshots.appendingPathComponent(".transaction.lock")
            let fd = try holdLock(w)
            close(fd)
            guard chownToNobody(lock) else { return ["could not give the lock file to another user"] }
            let run = w.macctl(["set", "t.a", "true"])
            var failures = run.ok ? ["apply took a lock owned by another user"] : []
            if !w.headerIDs().isEmpty || !w.journalNames().isEmpty { failures.append("a header or journal was written") }
            return failures + expectPre(w, pre, "foreign lock")
        },
        Edge(name: "E-diskfull ENOSPC at the header write") { w in
            let command = try Ops.seedO2(w)
            let pre = w.state()
            let run = w.macctl(command, extra: ["MACCTL_TEST_ENOSPC": "header"])
            var failures = run.ok || run.killed ? ["expected a clean ENOSPC failure: \(run.summary)"] : []
            if !w.headerIDs().isEmpty || !w.journalNames().isEmpty { failures.append("a header or journal exists after ENOSPC at the header") }
            failures += expectPre(w, pre, "after ENOSPC at the header")
            // Space freed: recover has nothing to do, and the apply then works.
            let recover = w.macctl(["recover"])
            if !recover.ok { failures.append("recover: \(recover.summary)") }
            return failures + expectPre(w, pre, "after recover")
        },
        Edge(name: "E-diskfull ENOSPC at the second intent append") { w in
            let command = try Ops.seedO2(w)
            let pre = w.state()
            let run = w.macctl(command, extra: ["MACCTL_TEST_ENOSPC": "intent@2"])
            var failures = run.ok || run.killed ? ["expected a clean ENOSPC failure: \(run.summary)"] : []
            let ops = w.journalLines().values.flatMap { $0 }.compactMap { $0?["op"] as? String }
            if ops.filter({ $0 == "intent" }).count != 1 { failures.append("expected exactly one durable intent, journal ops: \(ops)") }
            // No preference write without a durable intent: change 2 was never written. Space freed:
            // recover (or the immediate rollback) brings everything back to pre.
            let recover = w.macctl(["recover"])
            if !recover.ok { failures.append("recover: \(recover.summary)") }
            failures += expectPre(w, pre, "after ENOSPC at intent 2 and recover")
            let again = w.macctl(["recover"])
            if !again.ok { failures.append("second recover: \(again.summary)") }
            return failures + expectPre(w, pre, "after a second recover")
        },
    ]

    /// Takes `snapshots/.transaction.lock` the way a running apply holds it (flock, exclusive).
    static func holdLock(_ w: World) throws -> Int32 {
        try FileManager.default.createDirectory(at: w.snapshots, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = open(w.snapshots.appendingPathComponent(".transaction.lock").path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw CocoaError(.fileLocking) }
        return fd
    }
}

@Suite struct EdgeCaseTests {
    /// Plan v3 §1.5 rows (23) plus four extra cases, 27 in all, pinned (Pat G1). The extras: R-g ×2,
    /// E-restore-drop, and E-lock's "symlink / foreign owner refused" item run as two cases.
    @Test func edgeTotalsMatchThePlan() {
        let rows: [(String, Int)] = [("E-torn", 3), ("E-corrupt", 2), ("E-lock", 4), ("E-gate", 2), ("E-hand", 2),
                                     ("E-forced", 1), ("E-diskfull", 2), ("E-perm", 2), ("E-legacy", 1), ("E-sensitive", 1),
                                     ("E-rollback-nocrash", 1), ("E-undo-ops", 1), ("E-mismatch", 1)]
        #expect(rows.map(\.1).reduce(0, +) == 23)
        for (row, count) in rows {
            let found = Edges.all.filter { $0.name.hasPrefix(row + " ") || $0.name.hasPrefix(row + ":") }.count
            #expect(found == count + (row == "E-lock" ? 1 : 0), "\(row): \(found) cases, plan v3 §1.5 has \(count)")
        }
        let extras = Edges.all.filter { $0.name.hasPrefix("R-g ") || $0.name.hasPrefix("E-restore-drop") }.count
        #expect(extras == 3)
        #expect(Edges.all.count == 27)
    }

    @Test func edgeCases() throws {
        let backend = Config.backend
        var ran = 0, skipped: [String] = []
        // The ordinary `swift test` (no MACCTL_CRASH_BACKEND) runs only the first three (E-torn).
        let edges = Config.full ? Edges.all : Array(Edges.all.prefix(3))
        for (index, edge) in edges.enumerated() where Config.owns(index) {
            if edge.fakeOnly && backend != .fake { skipped.append(edge.name); continue }
            if edge.needsNonRoot && geteuid() == 0 { skipped.append(edge.name); continue }
            if edge.needsForeignOwner && !canChownToNobody { skipped.append(edge.name); continue }
            let specs = edge.name.hasPrefix("E-gate") || edge.name.hasPrefix("E-forced") || edge.name.hasPrefix("E-perm journal dir")
                || edge.name.hasPrefix("E-legacy") || edge.name.hasPrefix("R-g the next") || edge.name.hasPrefix("E-lock a symlinked")
                || edge.name.hasPrefix("E-lock transaction_busy") || edge.name.hasPrefix("E-lock get") || edge.name.hasPrefix("E-lock a lock file owned")
                ? Edges.o1 : edge.name.hasPrefix("E-corrupt with") ? Ops.all.first { $0.name == "O7" }!.specs : Edges.o2
            let w = try World(backend: backend, specs: specs)
            defer { w.cleanup() }
            do {
                for failure in try edge.run(w) { Issue.record(Comment(rawValue: "\(edge.name): \(failure)")) }
            } catch {
                Issue.record(Comment(rawValue: "\(edge.name): \(error)"))
            }
            ran += 1
        }
        Config.report("crash-matrix edge \(backend.rawValue) shard \(Config.shard.index)/\(Config.shard.count): edge=\(ran) skipped=\(skipped.count)\(skipped.isEmpty ? "" : " (\(skipped.joined(separator: "; ")))")")
    }
}
