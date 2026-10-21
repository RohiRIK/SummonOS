import Foundation
import Testing

/// Plan v3 §1: every op × every failpoint (single), × every recover failpoint (double), plus
/// idempotence. Without `MACCTL_CRASH_BACKEND` only O1 runs (smoke), on the fake store.
@Suite struct CrashMatrixTests {
    static var ops: [Op] { Config.full ? Ops.all : Ops.all.filter { $0.name == "O1" } }

    @Test(arguments: CrashMatrixTests.ops.map(\.name))
    func matrix(_ name: String) throws {
        let op = try #require(Ops.all.first { $0.name == name })
        let (_, failures) = try runMatrix(op, backend: Config.backend)
        for failure in failures { Issue.record(Comment(rawValue: failure)) }
    }

    /// Plan v3 totals, pinned (Pat G1/G3): 120 single, 422 double (v3 said 416; the +6 are RE after
    /// H1), 120 idempotence. Per op, so a lost or extra recover point fails here even when a shard
    /// would not notice. Counts every case without sharding, so it runs once per backend (shard 1).
    static let expectedDoubles = ["O1": 35, "O2": 129, "O3": 75, "O4": 35, "O5": 30, "O6a": 55, "O6b": 63, "O7": 0]

    @Test func matrixTotalsMatchThePlan() throws {
        #expect(Ops.all.map(\.expectedPoints).reduce(0, +) == 120)
        #expect(Self.expectedDoubles.values.reduce(0, +) == 422)
        #expect(Set(Self.expectedDoubles.keys) == Set(Ops.all.map(\.name)))
        guard Config.full, Config.shard.index == 1 else { return }
        var single = 0, double = 0
        for op in Ops.all where !(op.fakeOnly && Config.backend != .fake) {
            let found = try discover(op, backend: Config.backend)
            single += found.points.count
            var opDoubles = 0
            if op.kind == .mutation {
                for point in found.points {
                    opDoubles += try crashCase(op, backend: Config.backend, first: point, second: nil, reference: found.reference).recoverPoints.count
                }
            }
            #expect(opDoubles == Self.expectedDoubles[op.name], "\(op.name): \(opDoubles) double crashes, plan expects \(Self.expectedDoubles[op.name] ?? -1)")
            double += opDoubles
        }
        let fakeOnly = Ops.all.filter { $0.fakeOnly && Config.backend != .fake }
        let expectedSingle = 120 - fakeOnly.map(\.expectedPoints).reduce(0, +)
        let expectedDouble = 422 - fakeOnly.compactMap { Self.expectedDoubles[$0.name] }.reduce(0, +)
        #expect(single == expectedSingle)
        #expect(double == expectedDouble)
        Config.report("crash-matrix totals \(Config.backend.rawValue): single=\(single)/\(expectedSingle) double=\(double)/\(expectedDouble) idempotence=\(single) edges=\(Edges.all.count)")
    }

    /// Every template `MACCTL_FAILPOINT=list` prints is reached by some op (fake store, all ops).
    @Test func everyListedFailpointIsReached() throws {
        let w = try World(backend: .fake, specs: Ops.all[0].specs)
        defer { w.cleanup() }
        var env = w.environment
        env["MACCTL_FAILPOINT"] = "list"
        let listed = spawn(Config.binary, [], environment: env, in: w.root)
        #expect(listed.ok, "\(listed.summary)")
        let templates = Set(listed.out.split(separator: "\n").map(String.init))
        let adr: Set<String> = ["H1", "K1", "K2", "E1", "K3", "Ii.1", "Ii.2", "Ii.3", "Wi.1", "Wi.2", "Ai.1", "Ai.2",
                                "Fi.1", "Fi.2", "RIj", "RVj", "R0", "RE"]
        #expect(templates == adr, "MACCTL_FAILPOINT=list must print exactly the ADR D2 names")
        var reached: Set<String> = []
        for op in Ops.all {
            let found = try discover(op, backend: .fake)
            reached.formUnion(found.points.map(template(of:)))
        }
        // Recover's own points: crash O2 at K2, then trace recover.
        let crashed = try World(backend: .fake, specs: Ops.o2Specs)
        defer { crashed.cleanup() }
        let command = try Ops.seedO2(crashed)
        #expect(crashed.macctl(command, failpoint: "K2").killed)
        reached.formUnion(crashed.macctl(["recover"], failpoint: "trace").tracedPoints.map(template(of:)))
        #expect(templates.subtracting(reached).isEmpty, "never reached: \(templates.subtracting(reached).sorted())")
    }

    /// Negative control: the oracle must see a change that was not rolled back and a type change
    /// (`<real>64</real>` → `<integer>64</integer>`), or every PASS above would be meaningless.
    @Test func oracleDetectsLeftoversAndTypeChanges() throws {
        let w = try World(backend: Config.backend, specs: Ops.o2Specs)
        defer { w.cleanup() }
        let command = try Ops.seedO2(w)
        let pre = w.state()
        #expect(w.macctl(command, failpoint: "A2.2").killed)
        #expect(w.state() != pre, "a crashed, unrecovered apply must differ from pre")
        #expect(w.macctl(["recover"]).ok)
        #expect(w.state() == pre)
        try w.seed(w.a, "B", .int(64))
        #expect(w.state() != pre, "real 64 and integer 64 must differ")
    }

    /// The K3 rule: `completed` after a crash passes (via undo) only at K3.
    @Test func completedAfterANonK3CrashFails() throws {
        #expect(completedSessions(after: "K3@1", statuses: ["s": "completed"]).undo == ["s"])
        #expect(completedSessions(after: "K3@1", statuses: ["s": "completed"]).failures.isEmpty)
        for point in ["E1@1", "K2@1", "A1.2@1", "H1@1"] {
            let check = completedSessions(after: point, statuses: ["s": "completed"])
            #expect(check.undo.isEmpty && check.failures.count == 1, "\(point)")
        }
        #expect(!completedSessions(after: nil, statuses: ["s": "completed"]).failures.isEmpty)
        #expect(completedSessions(after: "E1@1", statuses: ["s": "recovered"]).failures.isEmpty)

        // Live: crash at E1, then forge the bug (a `session_end{completed}` line) and recover.
        let w = try World(backend: Config.backend, specs: Ops.all[0].specs)
        defer { w.cleanup() }
        try w.seed(w.a, "A", .bool(false))
        #expect(w.macctl(["set", "t.a", "true"], failpoint: "E1").killed)
        let file = try #require(w.journalNames().first.map { w.journal.appendingPathComponent($0) })
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data(#"{"op":"session_end","outcome":"completed","seq":99,"ts":"2026-10-20T00:00:00Z","v":1}"#.utf8 + [0x0a]))
        handle.closeFile()
        #expect(w.macctl(["recover"]).ok)
        let check = completedSessions(after: "E1@1", statuses: w.statuses())
        #expect(check.failures.count == 1, "a forged completed session must fail the case: \(check)")
    }
}

