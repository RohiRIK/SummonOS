import Foundation

/// What `undo` can promise for one setting, stated before anything is written, so an agent knows the
/// limits of a change up front instead of finding them in a `partial_restore`.
///
/// The guarantee is per backend: CFPreferences keys come back exactly (presence, type and value, read
/// back after the restore); AppleScript settings come back by value only; the wallpaper comes back
/// only while the old picture file and display still exist; a sensitive setting's prior is kept as a
/// keyed hash, so undo can detect a change but cannot write the old value back. Side effects (process
/// restarts, a created folder, logout) are never undone.
public struct RecoveryContract: Sendable, Hashable, Codable {
    public enum Restore: String, Sendable, Hashable, Codable {
        /// Absent, explicit and inherited priors are told apart; restore deletes or writes the exact type.
        case exact
        /// The old value is written back; an unset value cannot be told from a set one.
        case value
        /// Like `value`, but only while what the old value points at still exists.
        case conditional
        /// The prior is stored as a keyed hash: undo detects changes but restores only deletions.
        case compareOnly = "compare_only"
    }

    public let restore: Restore
    /// Prior states recorded as different cases (undo of `absent` deletes; of `explicit` writes back).
    public let priorStates: [PriorState.Kind]
    /// Every restore is read back; one that did not take is reported, never claimed as restored.
    public let verifiedByReadBack: Bool
    /// A key changed by someone else after macctl wrote it is left alone and reported (`--force` overwrites).
    public let handEdits: String
    /// What undo does not take back (a restart already happened; a created folder stays).
    public let notUndone: [String]
    /// Conditions and limits in one line each.
    public let notes: [String]
}

extension Setting {
    public var recovery: RecoveryContract {
        var notUndone: [String] = []
        for effect in after {
            switch effect {
            case .restart(let process): notUndone.append("restart:\(process) (undo restarts it again)")
            case .logout: notUndone.append("logout (undo also needs a logout to take effect)")
            case .relaunchApps: notUndone.append("relaunch-apps (open apps keep the old look until reopened)")
            }
        }
        if case .path = type, case .defaults = backend {
            notUndone.append("creates-folder (a folder macctl created is not deleted)")
        }
        var notes: [String] = []
        let restore: RecoveryContract.Restore
        let states: [PriorState.Kind]
        switch backend {
        case .defaults:
            restore = sensitive ? .compareOnly : .exact
            states = [.absent, .explicit, .inherited]
            if scope == .currentHost { notes.append("currentHost (ByHost) key: only this Mac's value is written and restored.") }
            if sensitive { notes.append("Sensitive: the journal keeps a keyed hash, so an old value cannot be written back.") }
        case .appleScript:
            restore = .value
            states = [.explicit]
            notes.append("Read and written through AppleScript: the old value is written back; there is no unset state.")
        case .wallpaper:
            restore = .conditional
            states = [.explicit]
            notes.append("Each display's old picture is restored only while its file exists and the display is connected.")
        }
        return RecoveryContract(restore: restore, priorStates: states, verifiedByReadBack: true,
                                handEdits: "left alone and reported (partial_restore); undo --force overwrites",
                                notUndone: notUndone, notes: notes)
    }

    /// True when this setting exists on `osVersion` (`"26.6.2"`). An unreadable version allows it.
    public func isAvailable(on osVersion: String) -> Bool {
        guard let minimumOS else { return true }
        guard let have = OSVersion(osVersion), let need = OSVersion(minimumOS) else { return true }
        return have >= need
    }
}

/// A dotted macOS version (`27`, `26.1`, `15.6.1`), compared numerically.
public struct OSVersion: Sendable, Hashable, Comparable {
    public let parts: [Int]

    public init?(_ text: String) {
        let pieces = text.trimmingCharacters(in: .whitespaces).split(separator: ".")
        let numbers = pieces.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == pieces.count else { return nil }
        // Trailing zeros dropped, so `27` and `27.0` are equal and hash alike.
        var trimmed = numbers
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        parts = trimmed
    }

    public static func < (a: OSVersion, b: OSVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

/// `macctl undo --dry-run`: what undo would do to each change, read-only. Predicts the same walk the
/// real undo runs (same checks, same order), so `wouldSucceed` false means undo would end in
/// `partial_restore`.
public struct UndoPreview: Sendable, Hashable, Codable {
    public enum Action: String, Sendable, Hashable, Codable {
        /// Write the old value back (explicit prior).
        case restore
        /// Delete the key so the absent or inherited state returns.
        case delete
        /// Already at the old state: nothing is written.
        case alreadyRestored = "already_restored"
        /// Changed by someone else since macctl wrote it: left alone (overwritten with --force).
        case handEdited = "hand_edited"
        /// The old value can no longer be written (a hash-only prior, a deleted wallpaper file).
        case cannotRestore = "cannot_restore"
    }

    public struct Item: Sendable, Hashable, Codable {
        public let id: String
        public let action: Action
        /// The value now (nil when unset or sensitive).
        public let current: Value?
        /// The value undo leaves (nil when it deletes, or when sensitive).
        public let restoresTo: Value?
        public let reason: String?
    }

    public let snapshotID: String
    public let force: Bool
    /// Newest change first, the order undo walks them.
    public let items: [Item]
    public let notes: [String]

    public var wouldSucceed: Bool { !items.contains { $0.action == .handEdited || $0.action == .cannotRestore } }

    private enum CodingKeys: String, CodingKey { case snapshotID, force, items, notes, wouldSucceed }

    public init(snapshotID: String, force: Bool, items: [Item], notes: [String]) {
        self.snapshotID = snapshotID
        self.force = force
        self.items = items
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snapshotID = try c.decode(String.self, forKey: .snapshotID)
        force = try c.decode(Bool.self, forKey: .force)
        items = try c.decode([Item].self, forKey: .items)
        notes = try c.decode([String].self, forKey: .notes)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(snapshotID, forKey: .snapshotID)
        try c.encode(force, forKey: .force)
        try c.encode(items, forKey: .items)
        try c.encode(notes, forKey: .notes)
        try c.encode(wouldSucceed, forKey: .wouldSucceed)
    }
}
