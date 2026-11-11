import Foundation

/// Delivery identities survive log replacement/trimming. Only terminal events occupy the ledger;
/// notification identity is defined by EventAnnouncer (run/file on new records).
public struct EventDeliveryLedger: Sendable {
    private let capacity: Int
    private var order: [String] = []
    private var identities: Set<String> = []

    public init(capacity: Int = 4_096) { self.capacity = max(1, capacity) }

    /// The first read establishes the app-launch baseline. Subsequent reads return only new records,
    /// even if a replacement file replays events or its timestamps run backwards.
    public mutating func receive(_ events: [LoggedEvent], baseline: Bool = false) -> [LoggedEvent] {
        var fresh: [LoggedEvent] = []
        for event in events {
            guard let announcement = EventAnnouncer.announcement(event) else { continue }
            guard identities.insert(announcement.id).inserted else { continue }
            order.append(announcement.id)
            if !baseline { fresh.append(event) }
        }
        if order.count > capacity {
            order.removeFirst(order.count - capacity)
            identities = Set(order)
        }
        return fresh
    }
}
