import Foundation

/// What changed on this Mac between two `MacContext` snapshots, as Activity events (`mac.*` kinds) that agents read
/// with `summon events --kind mac`, `--follow`, or the MCP tool `mac_events`. Only crossings are events, so a Mac
/// that stays low on disk logs it once, not every minute.
public enum MacEvents {
    public static let lowDiskGB = 20
    public static let lowBattery = 20
    public static let veryLowBattery = 10

    public static func changes(from old: MacContext?, to new: MacContext, now: Date = Date()) -> [LoggedEvent] {
        guard let old else { return [] }
        var events: [LoggedEvent] = []
        func add(_ kind: String, _ title: String, _ detail: String? = nil) {
            events.append(LoggedEvent(time: now, kind: "mac." + kind, title: title, detail: detail))
        }

        if let was = old.network, let now = new.network {
            if was.online && !now.online { add("network", "Network went offline") }
            if !was.online && now.online { add("network", "Back online" + (now.primaryInterface.map { " via \($0)" } ?? "")) }
            if was.vpn != now.vpn { add("network", now.vpn ? "VPN connected" : "VPN disconnected") }
        }

        if let was = mainVolume(old), let now = mainVolume(new) {
            if was.freeGB >= lowDiskGB && now.freeGB < lowDiskGB {
                add("disk", "Low disk space: \(now.freeGB) GB free on \(now.name)", "Under \(lowDiskGB) GB; macOS and apps slow down or fail to save.")
            }
            if was.freeGB < lowDiskGB && now.freeGB >= lowDiskGB { add("disk", "Disk space OK again: \(now.freeGB) GB free on \(now.name)") }
        }

        if let was = old.power, let now = new.power {
            if let before = was.battery, let after = now.battery, now.charging != true {
                if before >= veryLowBattery && after < veryLowBattery { add("battery", "Battery very low (\(after)%)") }
                else if before >= lowBattery && after < lowBattery { add("battery", "Battery low (\(after)%)") }
            }
            let hot = ["serious", "critical"]
            if !hot.contains(was.thermal) && hot.contains(now.thermal) { add("thermal", "Mac is running hot (thermal \(now.thermal))") }
            if hot.contains(was.thermal) && !hot.contains(now.thermal) { add("thermal", "Mac cooled down (thermal \(now.thermal))") }
        }

        if let was = old.displays?.count, let now = new.displays?.count, was != now {
            add("display", now > was ? "Display connected (\(now) now)" : "Display disconnected (\(now) now)")
        }
        return events
    }

    /// The startup volume, else the first one.
    static func mainVolume(_ context: MacContext) -> MacContext.Volume? {
        context.storage?.first { $0.path == "/" } ?? context.storage?.first
    }
}
