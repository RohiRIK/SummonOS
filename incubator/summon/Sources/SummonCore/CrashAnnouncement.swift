import Foundation

/// How Summon announces a new crash: its own floating alert (with the top frame and Diagnose), or a macOS
/// notification banner that stays in Notification Center. One of them, never both (Settings › Notifications).
public enum CrashAlertStyle: String, Sendable, CaseIterable, Identifiable {
    case summon
    case banner

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .summon: return "Summon alert"
        case .banner: return "macOS notification"
        }
    }

    public static let `default`: CrashAlertStyle = .summon
}

/// What one crash scan announces. A scan can find several reports at once (after sleep, or a crash loop): the
/// Summon alert shows the newest and counts the rest, banners group per program, and routine memory kills
/// (`CrashReport.isRoutine`) are listed in the panel only.
public struct CrashAnnouncementPlan: Sendable, Equatable {
    /// The report the floating alert shows, if any.
    public var alert: CrashReport?
    /// How many other new reports the alert stands for.
    public var alsoNew: Int
    /// Reports posted as banners, oldest first.
    public var banners: [CrashReport]

    /// Banners past this many in one scan collapse into the last one's group; the panel lists every report.
    public static let maxBanners = 3

    public static func make(_ reports: [CrashReport], style: CrashAlertStyle, canPostBanners: Bool) -> CrashAnnouncementPlan {
        let worth = reports.filter { !$0.isRoutine }
        guard !worth.isEmpty else { return CrashAnnouncementPlan(alert: nil, alsoNew: 0, banners: []) }
        if style == .banner && canPostBanners {
            // One banner per program (its newest report), so a crash loop is one notification, not twenty.
            var newestByProgram: [String: CrashReport] = [:]
            var order: [String] = []
            for report in worth {
                let key = CrashWatcher.muteKey(report.program)
                if newestByProgram[key] == nil { order.append(key) }
                newestByProgram[key] = report
            }
            let banners = order.compactMap { newestByProgram[$0] }
            return CrashAnnouncementPlan(alert: nil, alsoNew: 0, banners: Array(banners.suffix(maxBanners)))
        }
        // Reports come oldest first: the newest is the one most likely still on screen.
        return CrashAnnouncementPlan(alert: worth.last, alsoNew: worth.count - 1, banners: [])
    }
}
