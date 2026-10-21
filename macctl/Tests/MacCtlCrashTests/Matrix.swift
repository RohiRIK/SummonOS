import Foundation

/// One operation of plan v3 §1.3. `prepare` seeds the prior state (and any fixture) and returns the
/// rollback oracle `pre` and the command that is crashed.
struct Op: Sendable {
    enum Kind { case mutation, recoverOnly }
    let name: String
    let specs: [Spec]
    var kind: Kind = .mutation
    var fakeOnly = false
    /// Uninterrupted run: `nil` = must succeed; otherwise the error code it must return.
    var expectedError: String? = nil
    /// Plan v3 §1.3 point count (7N + 5 for an apply).
    let expectedPoints: Int
    let prepare: @Sendable (World) throws -> (pre: [String: String], command: [String])
}

enum Ops {
    static let o2Specs = [
        Spec(id: "t.a", type: "int", key: "B", storage: "int", after: ["restart:Dock"]),
        Spec(id: "t.b", type: "string", domain: .b, key: "C", storage: "string", after: ["restart:Finder"]),
        Spec(id: "t.c", type: "string", key: "D", storage: "string"),
    ]

    /// (b) explicit real 64.0 → int 40 (type canary), (a) absent → "x" in the second domain, (b) string.
    static func seedO2(_ w: World) throws -> [String] {
        try w.seed(w.a, "B", .real(64))
        try w.seed(w.a, "D", .string("old"))
        return ["apply", try w.writeProfile(["t.a": 40, "t.b": "x", "t.c": "new"])]
    }

    static let all: [Op] = [
        Op(name: "O1", specs: [Spec(id: "t.a", type: "bool", key: "A", storage: "bool")], expectedPoints: 12) { w in
            try w.seed(w.a, "A", .bool(false))
            return (w.state(), ["set", "t.a", "true"])
        },
        Op(name: "O2", specs: o2Specs, expectedPoints: 26) { w in
            let command = try seedO2(w)
            return (w.state(), command)
        },
        Op(name: "O3", specs: [Spec(id: "t.a", type: "string", key: "I", storage: "string"),
                               Spec(id: "t.b", type: "bool", key: "J", storage: "bool")], expectedPoints: 19) { w in
            // (c) inherited: the fake's global layer; on cfprefs the other host scope of the same
            // test domain (never the real -g).
            if w.backend == .fake { try w.seed("NSGlobalDomain", "I", .string("g")) }
            else { try w.seed(w.a, "I", .string("g"), currentHost: true) }
            return (w.state(), ["apply", try w.writeProfile(["t.a": "local", "t.b": true])])
        },
        Op(name: "O4", specs: [Spec(id: "t.a", type: "bool", key: "H", storage: "bool", host: "currentHost")],
           expectedPoints: 12) { w in
            try w.seed(w.a, "H", .bool(true))  // anyHost value present; must stay untouched
            return (w.state(), ["set", "t.a", "false"])
        },
        Op(name: "O5", specs: o2Specs, expectedPoints: 6) { w in
            let command = try seedO2(w)
            let pre = w.state()
            let applied = w.macctl(command)
            guard applied.ok, let id = w.headerIDs().first else { throw HarnessError("O5 setup apply: \(applied.summary)") }
            return (pre, ["undo", id])
        },
        Op(name: "O6a", specs: o2Specs, fakeOnly: true, expectedError: "mutation_failed", expectedPoints: 18) { w in
            let command = try seedO2(w)
            try w.knob(".fail-writes.plist", ["\(w.b)/C"])
            return (w.state(), command)
        },
        Op(name: "O6b", specs: o2Specs, fakeOnly: true, expectedError: "mutation_failed", expectedPoints: 20) { w in
            let command = try seedO2(w)
            try w.knob(".drop-writes.plist", ["\(w.b)/C"])
            return (w.state(), command)
        },
        Op(name: "O7", specs: [Spec(id: "t.a", type: "bool", key: "A", storage: "bool"),
                               Spec(id: "t.b", type: "string", domain: .b, key: "C", storage: "string")],
           kind: .recoverOnly, expectedPoints: 7) { w in
            try w.seed(w.a, "A", .bool(false))
            let pre = w.state()
            try Ops.twoUnresolvedSessions(w)
            return (pre, ["recover"])
        },
    ]

    /// O7 fixture: session A crashed at A1.2 in the main root; session B (one minute later, so a
    /// distinct id) crashed at A1.2 in a second root; then B's header and journal are merged in.
    /// The gate forbids creating B live next to an unresolved A.
    static func twoUnresolvedSessions(_ w: World, firstCommand: [String] = ["set", "t.a", "true"],
                                      secondCommand: [String] = ["set", "t.b", "x"]) throws {
        let main = w.stateDirectory
        let first = w.macctl(firstCommand, failpoint: "A1.2")
        guard first.killed else { throw HarnessError("O7 session A: \(first.summary)") }
        w.stateDirectory = w.root.appendingPathComponent("y")
        w.now = Config.now + 60
        defer { w.stateDirectory = main; w.now = Config.now }
        let second = w.macctl(secondCommand, failpoint: "A1.2")
        guard second.killed else { throw HarnessError("O7 session B: \(second.summary)") }
        let fm = FileManager.default
        for (sub, suffix) in [("snapshots", ".json"), ("journal", ".jsonl")] {
            let from = w.stateDirectory.appendingPathComponent(sub)
            for name in try fm.contentsOfDirectory(atPath: from.path) where name.hasSuffix(suffix) && !name.hasPrefix(".") {
                try fm.moveItem(at: from.appendingPathComponent(name),
                                to: main.appendingPathComponent(sub).appendingPathComponent(name))
            }
        }
    }
}

/// What an uninterrupted recover left (domains and normalized journal): the rerun-equality reference.
struct Reference {
    let state: [String: String]
    let journal: [String]
}

struct Tally {
    var single = 0, double = 0, idempotence = 0, edge = 0, skipped = 0
}

func describeDiff(_ expected: [String: String], _ actual: [String: String]) -> String {
    let keys = Set(expected.keys).union(actual.keys).sorted()
    return keys.filter { expected[$0] != actual[$0] }.map {
        "\($0): expected \(expected[$0]?.prefix(300) ?? "nil") got \(actual[$0]?.prefix(300) ?? "nil")"
    }.joined(separator: "; ")
}

/// Plan v3 §1.1 steps 5-6, everything except the byte comparison.
func invariants(_ w: World, headers: [String: World.HeaderPrint]) -> [String] {
    var failures: [String] = []
    for (name, lines) in w.journalLines() {
        let torn = lines.enumerated().filter { $0.element == nil }.map(\.offset)
        if torn.count > 1 || (torn.count == 1 && torn[0] != lines.count - 1) {
            failures.append("\(name): unreadable lines \(torn) (only a torn last line is allowed)")
        }
        let records = lines.compactMap { $0 }
        // Outcome and revert lines carry `ref` = the intent's seq.
        func seqs(_ ops: Set<String>) -> Set<Int> {
            Set(records.filter { ops.contains($0["op"] as? String ?? "") }.compactMap { $0["seq"] as? Int })
        }
        func refs(_ ops: Set<String>) -> Set<Int> {
            Set(records.filter { ops.contains($0["op"] as? String ?? "") }.compactMap { $0["ref"] as? Int })
        }
        let openIntents = seqs(["intent"]).subtracting(refs(["applied", "failed", "flagged"]))
        let openReverts = refs(["revert_intent"]).subtracting(refs(["reverted", "revert_flagged"]))
        if !openIntents.isEmpty { failures.append("\(name): intents without an outcome \(openIntents.sorted())") }
        if !openReverts.isEmpty { failures.append("\(name): revert_intents without an outcome \(openReverts.sorted())") }
        if records.last?["op"] as? String != "session_end" { failures.append("\(name): last line is not session_end") }
        if w.mode(w.journal.appendingPathComponent(name)) != 0o600 { failures.append("\(name): mode is not 0600") }
    }
    if !w.journalNames().isEmpty, w.mode(w.journal) != 0o700 { failures.append("journal dir mode is not 0700") }
    let pending = w.statuses().filter { $0.value == "pending" }
    if !pending.isEmpty { failures.append("still pending after recover: \(pending.keys.sorted())") }
    if !w.lockIsFree() { failures.append("transaction lock still held") }
    let now = w.headerPrints()
    if Set(now.keys) != Set(headers.keys) { failures.append("headers changed: \(headers.keys.sorted()) -> \(now.keys.sorted())") }
    for (id, print) in headers {
        guard let current = now[id] else { continue }
        if current != print { failures.append("header \(id) rewritten (inode/mtime/bytes changed)") }
        let status = ((try? JSONSerialization.jsonObject(with: current.bytes)) as? [String: Any])?["status"] as? String
        if status != "pending" { failures.append("header \(id) status is \(status ?? "nil"), not pending") }
        if w.mode(w.snapshots.appendingPathComponent("\(id).json")) != 0o600 { failures.append("header \(id) mode is not 0600") }
    }
    return failures
}

/// Sessions `completed` after a crash: legitimate only for a crash at K3 (ADR D3 row 8), where the
/// oracle is checked after `undo`; after any other point (or a crash inside recover) it is a FAIL.
func completedSessions(after first: String?, statuses: [String: String]) -> (undo: [String], failures: [String]) {
    let ids = statuses.filter { $0.value == "completed" }.map(\.key).sorted()
    guard !ids.isEmpty else { return ([], []) }
    if let first, template(of: first) == "K3" { return (ids, []) }
    return ([], ids.map { "session \($0) completed after a crash at \(first ?? "recover")" })
}

/// One crash case of a mutation op: crash at `first`, optionally crash recover at `second`, then
/// recover, oracle, invariants and (single crashes) idempotence.
func crashCase(_ op: Op, backend: Backend, first: String, second: String?, reference: Reference?)
    throws -> (failures: [String], recoverPoints: [String], reference: Reference?) {
    let w = try World(backend: backend, specs: op.specs)
    defer { w.cleanup() }
    let setup = try op.prepare(w)
    var failures: [String] = []
    let tag = "\(op.name) \(first)\(second.map { " + recover@\($0)" } ?? "")"
    if op.kind == .mutation {
        let crashed = w.macctl(setup.command, failpoint: first)
        guard crashed.killed else { return (["\(tag): did not die of SIGKILL: \(crashed.summary)"], [], nil) }
    }
    let headers = w.headerPrints()
    let recoverCrash = op.kind == .recoverOnly ? first : second
    if let recoverCrash {
        let crashed = w.macctl(["recover"], failpoint: recoverCrash)
        if !crashed.killed { failures.append("\(tag): recover did not die at \(recoverCrash): \(crashed.summary)") }
    }
    let traced = op.kind == .mutation && second == nil
    let recovered = w.macctl(["recover"], failpoint: traced ? "trace" : nil)
    if !recovered.ok { failures.append("\(tag): recover failed: \(recovered.summary)") }
    let observed = Reference(state: w.state(), journal: w.normalizedJournal())
    if let reference {
        if reference.state != observed.state {
            failures.append("\(tag): rerun differs from an uninterrupted recover (domains): \(describeDiff(reference.state, observed.state))")
        }
        if reference.journal != observed.journal {
            let diff = zip(reference.journal, observed.journal).first { $0 != $1 }
            failures.append("\(tag): rerun differs from an uninterrupted recover (journal, \(reference.journal.count) vs \(observed.journal.count) lines): \(diff.map { "\($0.0) vs \($0.1)" } ?? "")")
        }
    }
    // K3: the session already completed, so recover wrote nothing; the oracle applies after undo.
    // At any other point a `completed` session after a crash is itself a bug (Max, #63 review).
    let completed = completedSessions(after: op.kind == .mutation ? first : nil, statuses: w.statuses())
    failures += completed.failures.map { "\(tag): \($0)" }
    for id in completed.undo {
        let undo = w.macctl(["undo", id])
        if !undo.ok { failures.append("\(tag): undo \(id) after recover: \(undo.summary)") }
    }
    let end = w.state()
    if end != setup.pre { failures.append("\(tag): not rolled back to pre: \(describeDiff(setup.pre, end))") }
    failures += invariants(w, headers: headers).map { "\(tag): \($0)" }
    if second == nil {
        let journal = w.journalBytes()
        let again = w.macctl(["recover"])
        if !again.ok { failures.append("\(tag): second recover failed: \(again.summary)") }
        if w.journalBytes() != journal { failures.append("\(tag): second recover appended journal lines") }
        if w.state() != end { failures.append("\(tag): second recover changed a domain") }
        failures += invariants(w, headers: headers).map { "\(tag) (second recover): \($0)" }
    }
    return (failures, traced ? recovered.tracedPoints : [], observed)
}

/// Uninterrupted run with `MACCTL_FAILPOINT=trace`: the case list for an op.
func discover(_ op: Op, backend: Backend) throws -> (points: [String], failures: [String], reference: Reference?) {
    let w = try World(backend: backend, specs: op.specs)
    defer { w.cleanup() }
    let setup = try op.prepare(w)
    let run = w.macctl(setup.command, failpoint: "trace")
    var failures: [String] = []
    switch op.expectedError {
    case nil where !run.ok: failures.append("\(op.name): uninterrupted run failed: \(run.summary)")
    case let code? where run.errorCode != code: failures.append("\(op.name): expected \(code), got \(run.summary)")
    default: break
    }
    if op.expectedError != nil || op.kind == .recoverOnly, w.state() != setup.pre {
        failures.append("\(op.name): uninterrupted run did not end at pre: \(describeDiff(setup.pre, w.state()))")
    }
    let reference = op.kind == .recoverOnly ? Reference(state: w.state(), journal: w.normalizedJournal()) : nil
    return (run.tracedPoints, failures, reference)
}

/// Runs one op's whole matrix slice: single crashes, the double crashes inside recover, idempotence.
func runMatrix(_ op: Op, backend: Backend, doubles: Bool = true) throws -> (Tally, [String]) {
    var tally = Tally()
    if op.fakeOnly && backend != .fake {
        Config.report("crash-matrix \(op.name) \(backend.rawValue): skipped (needs fake-store error injection)")
        tally.skipped = 1
        return (tally, [])
    }
    let found = try discover(op, backend: backend)
    var failures = found.failures
    if found.points.count != op.expectedPoints {
        failures.append("\(op.name): trace found \(found.points.count) points, plan v3 expects \(op.expectedPoints): \(found.points)")
    }
    for (index, point) in found.points.enumerated() where Config.owns(index) {
        let single = try crashCase(op, backend: backend, first: point, second: nil, reference: found.reference)
        tally.single += 1
        tally.idempotence += 1
        failures += single.failures
        guard doubles, op.kind == .mutation else { continue }
        for recoverPoint in single.recoverPoints {
            let double = try crashCase(op, backend: backend, first: point, second: recoverPoint, reference: single.reference)
            tally.double += 1
            failures += double.failures
        }
    }
    Config.report("crash-matrix \(op.name) \(backend.rawValue) shard \(Config.shard.index)/\(Config.shard.count): single=\(tally.single) double=\(tally.double) idempotence=\(tally.idempotence) failures=\(failures.count)")
    return (tally, failures)
}
