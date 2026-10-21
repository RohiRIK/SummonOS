import Foundation
#if canImport(CoreServices)
import CoreServices
#endif
#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if !canImport(Darwin)
import Glibc
/// Linux builds (journal/recovery CI) have no Carbon; keep the status mapping testable.
public typealias OSStatus = Int32
#endif

/// Checks TCC permissions without ever showing a prompt.
///
/// `granted` means "will not be refused": Automation that has not been asked yet (-1744) or whose
/// target is not running (-600) counts as granted, because the first real Apple Event shows the
/// consent prompt. Only an explicit denial blocks a write.
///
/// TCC attributes grants to the responsible process (the terminal or app that launched macctl),
/// so a result describes that host, not the macctl binary itself.
public struct SystemPermissionProbe: PermissionProbe {
    /// A probe result with a human detail line for `doctor`.
    public struct Check: Sendable, Hashable {
        public let granted: Bool
        public let detail: String

        public init(granted: Bool, detail: String) {
            self.granted = granted
            self.detail = detail
        }
    }

    private let homeDirectory: String

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    public func isGranted(_ permission: Permission) async -> Bool {
        await check(permission).granted
    }

    public func settingsURL(for permission: Permission) -> String {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        switch permission {
        case .automation: return base + "Privacy_Automation"
        case .accessibility: return base + "Privacy_Accessibility"
        case .fullDiskAccess: return base + "Privacy_AllFiles"
        }
    }

    /// Like `isGranted`, plus why. Never prompts.
    public func check(_ permission: Permission) async -> Check {
        switch permission {
        case .automation(let bundleID): return Self.automation(bundleID)
        case .accessibility: return Self.accessibility()
        case .fullDiskAccess: return fullDiskAccess()
        }
    }

    // MARK: Automation

    static func automation(_ bundleID: String) -> Check {
        #if canImport(CoreServices)
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else {
            return Check(granted: false, detail: "could not build an Apple Event target for \(bundleID)")
        }
        let status = AEDeterminePermissionToAutomateTarget(
            desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false
        )
        return automationCheck(status: status, bundleID: bundleID)
        #else
        return Check(granted: false, detail: "Automation checks need macOS")
        #endif
    }

    /// Maps an `AEDeterminePermissionToAutomateTarget` status. Split out so tests can cover it.
    static func automationCheck(status: OSStatus, bundleID: String) -> Check {
        switch status {
        case 0:
            return Check(granted: true, detail: "Automation of \(bundleID) is allowed")
        case -1743: // errAEEventNotPermitted
            return Check(granted: false, detail: "Automation of \(bundleID) was denied; allow it in System Settings")
        case -1744: // errAEEventWouldRequireUserConsent
            return Check(granted: true, detail: "Automation of \(bundleID) has not been asked yet; macOS will prompt on first use")
        case -600: // procNotFound
            return Check(granted: true, detail: "\(bundleID) is not running; macOS will prompt on first use if Automation was never asked")
        default:
            return Check(granted: false, detail: "Automation check for \(bundleID) failed (OSStatus \(status))")
        }
    }

    // MARK: Accessibility

    static func accessibility() -> Check {
        #if canImport(ApplicationServices)
        let trusted = AXIsProcessTrusted()
        return Check(
            granted: trusted,
            detail: trusted ? "Accessibility is allowed" : "Accessibility is not allowed for the app running macctl"
        )
        #else
        return Check(granted: false, detail: "Accessibility checks need macOS")
        #endif
    }

    // MARK: Full Disk Access

    enum ProbeResult: Equatable { case readable, denied, missing }

    /// Opens files only Full Disk Access can read. Avoids other apps' containers, which can raise
    /// the separate "access data from other apps" prompt on macOS 14+.
    func fullDiskAccess() -> Check {
        let candidates = [
            homeDirectory + "/Library/Safari/Bookmarks.plist",
            homeDirectory + "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for path in candidates {
            switch Self.probeFile(path) {
            case .readable:
                return Check(granted: true, detail: "Full Disk Access is allowed")
            case .denied:
                return Check(granted: false, detail: "Full Disk Access is not allowed for the app running macctl")
            case .missing:
                continue
            }
        }
        return Check(granted: false, detail: "could not determine Full Disk Access (no probe file found)")
    }

    static func probeFile(_ path: String) -> ProbeResult {
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return .readable
        }
        return errno == ENOENT ? .missing : .denied
    }
}
