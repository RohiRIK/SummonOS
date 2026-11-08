import Darwin
import Foundation

// Compiled together with the actual Sources/SummonCore/*.swift, never a stand-in implementation.
@main struct CoreAudit {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "fixture-terminal" {
            let paths = SummonPaths(home: URL(fileURLWithPath: args[2], isDirectory: true))
            try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
            let result = try await ProcessExecutor.run("/bin/sh", ["-c", "printf 'audit completion'" ])
            guard result.status == 0 else { throw AuditError.fixtureMismatch("child completion") }
            let runID = UUID().uuidString.lowercased()
            try EventLog(paths: paths).append(LoggedEvent(kind: EventKind.taskDone,
                title: "Audit completion fixture", detail: "Harmless shell child completed",
                refs: ["task": "audit-fixture", "run": runID]))
            guard EventLog(paths: paths).read().last?.refs["run"] == runID else {
                throw AuditError.fixtureMismatch("terminal persistence")
            }
            print("terminal persisted")
            return
        }
        guard args.count == 4 else { throw AuditError.invalidArguments }
        let home = URL(fileURLWithPath: args[1], isDirectory: true)
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        guard let repetitions = Int(args[3]), repetitions > 0 else { throw AuditError.invalidArguments }
        let paths = SummonPaths(home: home)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.state, withIntermediateDirectories: true)
        let log = EventLog(paths: paths)
        var metrics: [[String: Any]] = []
        var scenarios: [[String: Any]] = []
        func scenario(_ name: String, _ pass: Bool, _ info: [String: Any] = [:]) {
            scenarios.append(["name": name, "status": pass ? "passed" : "failed", "details": info])
        }
        func measure(_ label: String, count: Int, bytes: Int, _ call: () throws -> Int) throws {
            guard try call() == count else { throw AuditError.fixtureMismatch(label) }
            var samples: [Double] = []
            for _ in 0..<repetitions {
                let begin = DispatchTime.now().uptimeNanoseconds
                guard try call() == count else { throw AuditError.fixtureMismatch(label) }
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000)
            }
            samples.sort()
            let middle = repetitions / 2
            let median = repetitions.isMultiple(of: 2) ? (samples[middle-1] + samples[middle]) / 2 : samples[middle]
            let p95 = samples[Int(ceil(Double(repetitions) * 0.95)) - 1]
            metrics.append(["name": label, "count": count, "bytes": bytes, "warmup": 1,
                            "repetitions": repetitions, "median_ms": median, "p95_ms": p95,
                            "method": "nearest-rank p95 of complete wall-time reads"])
        }
        for count in [100, 2_000, 6_000] {
            let rows = (0..<count).map { index in
                "{\"detail\":\"result \(index)\",\"kind\":\"task.done\",\"refs\":{\"task\":\"audit\"},\"time\":\"2026-11-08T00:00:00Z\",\"title\":\"Task finished\"}"
            }
            try (rows.joined(separator: "\n") + "\n").write(to: log.file, atomically: true, encoding: .utf8)
            let size = (try fm.attributesOfItem(atPath: log.file.path)[.size] as! NSNumber).intValue
            try measure("EventLog.read", count: count, bytes: size) { log.read().count }
        }
        // Real JSON snapshot headers and checkpoints, not merely directory enumeration.
        try fm.createDirectory(at: paths.macctlSnapshots, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.config, withIntermediateDirectories: true)
        var snapshotBytes = 0
        for count in [0, 100, 1_000] {
            if count > 0 {
                let start = count == 100 ? 0 : 100
                for index in start..<count {
                    let id = String(format: "audit-%04d", index)
                    let snapshot = "{\"id\":\"\(id)\",\"createdAt\":\"2026-11-08T00:00:00Z\",\"changes\":[]}"
                    try snapshot.write(to: paths.macctlSnapshots.appendingPathComponent(id + ".json"), atomically: true, encoding: .utf8)
                    snapshotBytes += snapshot.utf8.count
                }
            }
            let checkpoints = (0..<count).map { index in
                "{\"id\":\"audit-\(index)\",\"label\":\"audit\",\"createdAt\":\"2026-11-08T00:00:00Z\"}"
            }.joined(separator: ",")
            try ("[" + checkpoints + "]").write(to: paths.config.appendingPathComponent("checkpoints.json"), atomically: true, encoding: .utf8)
            let fixtureBytes = snapshotBytes + checkpoints.utf8.count + 2 +
                (try fm.attributesOfItem(atPath: log.file.path)[.size] as! NSNumber).intValue
            try measure("ActivitySources.load", count: count, bytes: fixtureBytes) {
                let sources = ActivitySources.load(paths: paths, crashLimit: 0)
                guard sources.checkpoints.count == count else { throw AuditError.fixtureMismatch("checkpoints") }
                return sources.snapshots.count
            }
        }
        let before = (0..<1024).filter { fcntl(Int32($0), F_GETFD) != -1 }.count
        var successful = 0
        for index in 0..<50 {
            let file = home.appendingPathComponent("child-\(index).log")
            var options = ProcessOptions(); options.logFile = file
            let result = try await ProcessExecutor.run("/bin/sh", ["-c", "printf 'audit-output'"], options: options)
            let content = try String(contentsOf: file, encoding: .utf8)
            if result.status == 0 && result.output == "audit-output" && content == "audit-output" { successful += 1 }
        }
        let after = (0..<1024).filter { fcntl(Int32($0), F_GETFD) != -1 }.count
        scenario("success and descriptor cleanup", successful == 50 && before == after,
                 ["executions": successful, "fd_before": before, "fd_after": after])
        let longLine = String(repeating: "L", count: 70_000)
        var longOptions = ProcessOptions(); longOptions.logFile = home.appendingPathComponent("long-output.log")
        let longOutput = try await ProcessExecutor.run("/bin/sh", ["-c", "printf '%s' \"$1\"", "fixture", longLine], options: longOptions)
        let longLog = try String(contentsOf: longOptions.logFile!, encoding: .utf8)
        scenario("70 KB final child line retained in log", longOutput.status == 0 &&
                 longOutput.output == longLine && longLog == longLine,
                 ["utf8_bytes":longLog.utf8.count])
        let escaped = "escaped \\ \" newline\n😀"
        var escapedOptions = ProcessOptions(); escapedOptions.logFile = home.appendingPathComponent("escaped-output.log")
        let escapedOutput = try await ProcessExecutor.run("/bin/sh", ["-c", "printf '%s' \"$1\"", "fixture", escaped], options: escapedOptions)
        let escapedLog = try String(contentsOf: escapedOptions.logFile!, encoding: .utf8)
        scenario("escaped Unicode shell output preserved", escapedOutput.status == 0 &&
                 escapedOutput.output == escaped && escapedLog == escaped,
                 ["utf8_bytes":escapedLog.utf8.count])
        let failed = try await ProcessExecutor.run("/bin/sh", ["-c", "printf failed; exit 7"])
        scenario("nonzero execution", failed.status == 7 && failed.output == "failed", ["exit_status": Int(failed.status)])
        do { _ = try await ProcessExecutor.run("/nonexistent-summonos-audit", []); scenario("spawn failure", false) }
        catch { scenario("spawn failure", true, ["error_type": String(describing: type(of: error))]) }
        var options = ProcessOptions(); options.timeout = 0.08; options.terminationGrace = 0.01
        do { _ = try await ProcessExecutor.run("/bin/sh", ["-c", "sleep 5"], options: options); scenario("timeout", false) }
        catch { scenario("timeout", true, ["error_type": String(describing: type(of: error))]) }
        let running = Task { try await ProcessExecutor.run("/bin/sh", ["-c", "sleep 5"]) }
        try await Task.sleep(for: .milliseconds(50)); running.cancel()
        do { _ = try await running.value; scenario("cancellation", false) }
        catch { scenario("cancellation", error is CancellationError) }
        let task = RecurringTask(id: "audit", name: "Audit", prompt: "", agent: nil, schedule: TaskSchedule(kind: .daily))
        let folder = paths.taskLogs.appendingPathComponent("audit")
        try TaskStore(paths: paths).save([task])
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        let names = (0..<25).map { _ in UUID().uuidString.lowercased() }.sorted()
        for (index, name) in names.enumerated() {
            let file = folder.appendingPathComponent(name + ".log")
            try "fixture".write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(Double(24-index)*60)], ofItemAtPath: file.path)
        }
        let plan = SummonCleaner.plan(paths, tasks: [task], now: now.addingTimeInterval(25*60))
        let discarded = Set(plan.trash.map { URL(fileURLWithPath: $0.path).lastPathComponent })
        let actualOldest = Set(names.suffix(5).map { $0 + ".log" })
        scenario("25 UUID retention chronology", discarded == actualOldest,
                 ["selected": discarded.count, "newest_selected": discarded.contains(names.first! + ".log")])
        var movedUnderActiveLease: [URL] = []
        let held = try FileLease.acquireSync(paths.state.appendingPathComponent("locks/task-audit.lock"))
        withExtendedLifetime(held) {
            _ = SummonCleaner.apply(plan, paths: paths, now: now.addingTimeInterval(25*60)) { item in
                movedUnderActiveLease.append(item) // Never calls Trash; fixture-only injected observer.
            }
        }
        scenario("cleanup overlap active task lease", movedUnderActiveLease.isEmpty,
                 ["items_moved_while_active": movedUnderActiveLease.count])
        // Exercise the real finalization boundary, not just rejection of an unfitted raw event.
        let terminalRun = UUID().uuidString
        let terminalLog = folder.appendingPathComponent(terminalRun + ".log")
        try longLine.write(to: terminalLog, atomically: true, encoding: .utf8)
        let journal = TaskRunJournal(paths: paths, task: "audit")
        try journal.begin(TaskRunMarker(run: terminalRun, task: "audit", name: "Audit", file: terminalLog.path))
        let finalization = TaskRunFinalizer.finalize(TaskRunRecord(run: terminalRun, task: "audit", name: "Audit",
            outcome: .done, started: true, detail: longLine + escaped, logFile: terminalLog), log: log, journal: journal)
        let persisted = TaskResults.terminals(in: log.read()).filter { $0.run == terminalRun }
        let fullLogRetained = try String(contentsOf: terminalLog, encoding: .utf8) == longLine
        let markerCleared = try journal.pending().isEmpty
        scenario("oversized terminal finalized and delivered", finalization.persistence.isRecorded &&
                 persisted.count == 1 && persisted.first?.outcome == .done &&
                 (persisted.first?.event.detail?.utf8.count ?? .max) < EventLog.maxEventBytes &&
                 fullLogRetained && markerCleared,
                 ["full_log_bytes": longLine.utf8.count, "persisted_records": persisted.count])
        let concurrent = (0..<2).map { index in Task { try log.append(LoggedEvent(kind: EventKind.taskDone, title: "Done", detail: "escaped \\ \" 😀", refs: ["task": "audit", "run": "audit-\(index)"])) } }
        for child in concurrent { try await child.value }
        let completed = log.read().suffix(2)
        scenario("concurrent escaped terminal events", completed.count == 2 &&
                 Set(completed.compactMap { $0.refs["run"] }) == ["audit-0", "audit-1"] &&
                 completed.allSatisfy { $0.detail == "escaped \\ \" 😀" })
        let encoder: JSONSerialization.WritingOptions = [.sortedKeys, .prettyPrinted]
        try JSONSerialization.data(withJSONObject: metrics, options: encoder).write(to: output.appendingPathComponent("core-metrics.json"))
        try JSONSerialization.data(withJSONObject: scenarios, options: encoder).write(to: output.appendingPathComponent("core-scenarios.json"))
    }

    enum AuditError: Error { case invalidArguments, fixtureMismatch(String) }
}
