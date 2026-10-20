import Foundation

/// A journaled session, rebuilt from its JSONL lines (ADR D2). Read-only.
public struct Session: Sendable {
    public enum Outcome: String, Sendable { case applied, failed, flagged }
    public enum RevertState: Sendable, Equatable {
        /// `revert_intent` with no `reverted`/`revert_flagged` after it: outcome unknown.
        case open(JournalRecord)
        case reverted
        case flagged
    }

    public let id: String
    public let records: [JournalRecord]
    public let tornTail: Bool

    public init(id: String, records: [JournalRecord], tornTail: Bool) {
        self.id = id
        self.records = records
        self.tornTail = tornTail
    }

    public var start: JournalRecord? { records.first { $0.op == .sessionStart } }
    public var intents: [JournalRecord] { records.filter { $0.op == .intent } }
    public var createdAt: Date { records.first?.ts ?? Date(timeIntervalSince1970: 0) }
    public var nextSeq: Int { (records.map(\.seq).max() ?? 0) + 1 }

    /// The first `applied`/`failed`/`flagged` line for each intent seq.
    public var outcomes: [Int: Outcome] {
        var result: [Int: Outcome] = [:]
        for record in records {
            guard let ref = record.ref, result[ref] == nil else { continue }
            switch record.op {
            case .applied: result[ref] = .applied
            case .failed: result[ref] = .failed
            case .flagged: result[ref] = .flagged
            default: break
            }
        }
        return result
    }

    /// The latest revert state of each intent seq (a later `--force` walk can follow a flag).
    public var reverts: [Int: RevertState] {
        var result: [Int: RevertState] = [:]
        for record in records {
            guard let ref = record.ref else { continue }
            switch record.op {
            case .revertIntent: result[ref] = .open(record)
            case .reverted: result[ref] = .reverted
            case .revertFlagged: result[ref] = .flagged
            default: break
            }
        }
        return result
    }

    public var lastEnd: JournalRecord? { records.last { $0.op == .sessionEnd } }

    /// Every intent has an outcome and no revert is open.
    public var allTerminal: Bool {
        let outcomes = self.outcomes
        guard intents.allSatisfy({ outcomes[$0.seq] != nil }) else { return false }
        return !reverts.values.contains { if case .open = $0 { true } else { false } }
    }

    public var status: Snapshot.Status {
        guard let end = lastEnd, allTerminal, records.last?.op == .sessionEnd else { return .pending }
        return Snapshot.Status(rawValue: end.outcome ?? "") ?? .pending
    }

    /// Blocks new mutations until `macctl recover` (ADR Q4).
    public var unresolved: Bool { status == .pending }

    /// Settings flagged (unknown outcome or hand edit) and not reverted since.
    public var flaggedSettings: [String] {
        let bySeq = Dictionary(uniqueKeysWithValues: intents.map { ($0.seq, $0) })
        let outcomes = self.outcomes
        let reverts = self.reverts
        return intents.filter { outcomes[$0.seq] == .flagged || reverts[$0.seq] == .flagged }
            .compactMap { bySeq[$0.seq]?.settingID }
    }

    /// Seen through the snapshot model, so `snapshot list --json` and Summon keep working.
    public func snapshot(header: Snapshot?) -> Snapshot {
        let outcomes = self.outcomes
        let applied = intents.filter { outcomes[$0.seq] == .applied }.compactMap(\.settingID)
        let changes = header?.changes ?? intents.map { intent in
            Change(id: intent.settingID ?? "?", from: intent.prior?.displayValue,
                   to: intent.new?.value?.value ?? .string("(sensitive)"), prior: intent.prior, new: intent.new)
        }
        return Snapshot(id: id, createdAt: header?.createdAt ?? createdAt, changes: changes,
                        undoes: header?.undoes ?? start?.undoes, status: status, appliedSettings: applied,
                        failure: lastEnd?.reason)
    }
}

extension PriorState {
    /// Catalog-style scalar for `Change.from`: the explicit value, nil for absent/inherited.
    var displayValue: Value? { state == .explicit ? value?.value : nil }

    /// Whether the current exact-triple value is what this prior state left there.
    func isCurrent(_ current: TypedValue?, key: () throws -> Data) throws -> Bool {
        try restoredValue.matches(current, key: key)
    }
}
