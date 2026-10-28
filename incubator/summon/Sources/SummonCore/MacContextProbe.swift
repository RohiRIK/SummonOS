import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import IOKit.ps
import SystemConfiguration

/// Reads `MacContext` from the live system. Each section is read on its own, so one that fails is left out
/// instead of failing the snapshot. Nothing here prompts for a permission.
public enum MacContextProbe {
    /// For a one-shot command (the CLI); the menu app, Siri and MCP use `snapshot`, which keeps the main thread free.
    @MainActor
    public static func live(paths: SummonPaths, tools: ToolLocator, hidden: [ContextField], now: Date = Date()) -> MacContext {
        var context = basics(paths: paths, tools: tools, now: now)
        context.apps = apps()
        context.appearance = appearance(home: paths.home.path)
        return context.hiding(hidden)
    }

    /// The same snapshot off the main thread: the file checks (Full Disk Access, volumes, crash reports) wait as long
    /// as a File Provider takes to answer, which hung the menu (#119). Only the AppKit reads run on the main actor.
    public static func snapshot(paths: SummonPaths, tools: ToolLocator, hidden: [ContextField], now: Date = Date()) async -> MacContext {
        let home = paths.home.path
        let (apps, appearance, front) = await MainActor.run {
            (apps(title: false), appearance(home: home), NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
        var context = await Task.detached {
            var context = basics(paths: paths, tools: tools, now: now)
            context.apps = apps
            context.apps?.windowTitle = front.flatMap(focusedWindowTitle(pid:))
            return context
        }.value
        context.appearance = appearance
        return context.hiding(hidden)
    }

    /// Everything that needs no AppKit; safe off the main thread.
    static func basics(paths: SummonPaths, tools: ToolLocator, now: Date) -> MacContext {
        let home = paths.home.path
        var context = MacContext(generated: now, hidden: [])
        context.system = system()
        context.power = power()
        context.storage = storage(home: home)
        context.network = network()
        context.displays = displays()
        context.permissions = MacContext.Permissions(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess(),
            // Readable only with Full Disk Access; reading it is the standard check and asks for nothing.
            fullDiskAccess: FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db"))
        context.agents = MacContext.Agents(
            defaultAgent: DefaultAgentStore(paths: paths).load()?.id,
            installed: AgentRegistry.all.filter { tools.find($0.command) != nil }.map(\.id))
        context.recentCrashes = CrashWatcher(paths: paths).reports(since: now.addingTimeInterval(-24 * 60 * 60), limit: 99).count
        return context
    }

    static func system() -> MacContext.System {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        var macOS = "\(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        if let build = sysctlString("kern.osversion") { macOS += " (\(build))" }
        return MacContext.System(
            model: sysctlString("hw.model") ?? "Mac",
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown chip",
            memoryGB: Int((Double(info.physicalMemory) / 1_073_741_824).rounded()),
            macOS: macOS,
            hostname: SCDynamicStoreCopyComputerName(nil, nil) as String?,
            uptimeHours: (info.systemUptime / 360).rounded() / 10)
    }

    static func power() -> MacContext.Power {
        let info = ProcessInfo.processInfo
        let thermal: String = switch info.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        var battery: Int?
        var charging: Bool?
        var onAC = true
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? {
                onAC = type == kIOPMACPowerKey
            }
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Int,
                      let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                battery = current * 100 / max
                charging = description[kIOPSIsChargingKey] as? Bool
            }
        }
        return MacContext.Power(battery: battery, charging: charging, onAC: onAC,
                                lowPowerMode: info.isLowPowerModeEnabled, thermal: thermal)
    }

    static func storage(home: String) -> [MacContext.Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0,
                  let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
            return MacContext.Volume(name: values.volumeName ?? url.lastPathComponent,
                                     path: url.path.replacingOccurrences(of: home, with: "~"),
                                     freeGB: Int(free / 1_000_000_000), totalGB: total / 1_000_000_000)
        }
    }

    static func network() -> MacContext.Network {
        let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String
        return MacContext.Network(online: primary != nil, primaryInterface: primary, vpn: hasTunnelWithIPv4())
    }

    /// shortcut: a VPN is any utun/ipsec/ppp interface with an IPv4 address (iCloud's utuns carry IPv6 only);
    /// a per-app or IPv6-only VPN reads as off. Upgrade to NEVPNManager status if that matters.
    static func hasTunnelWithIPv4() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            if ["utun", "ipsec", "ppp"].contains(where: name.hasPrefix) { return true }
        }
        return false
    }

    static func displays() -> [MacContext.Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id in
            guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else { return nil }
            return MacContext.Display(width: mode.width, height: mode.height,
                                      scale: max(1, mode.pixelWidth / mode.width), main: CGDisplayIsMain(id) != 0)
        }
    }

    @MainActor
    static func apps(title: Bool = true) -> MacContext.Apps {
        let workspace = NSWorkspace.shared
        let front = workspace.frontmostApplication
        let running = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
        return MacContext.Apps(frontmost: front?.localizedName, frontmostBundleID: front?.bundleIdentifier,
                               windowTitle: title ? front.flatMap { focusedWindowTitle(pid: $0.processIdentifier) } : nil,
                               running: Array(Set(running)).sorted())
    }

    /// The focused window's title through Accessibility; nil without permission (never prompts).
    static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        let text = (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    @MainActor
    static func appearance(home: String) -> MacContext.Appearance {
        let global = UserDefaults.standard
        let wallpaper = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }?.path
        return MacContext.Appearance(
            dark: global.string(forKey: "AppleInterfaceStyle") == "Dark",
            accent: MacContext.accentName(global.object(forKey: "AppleAccentColor") as? Int),
            wallpaper: wallpaper?.replacingOccurrences(of: home, with: "~"))
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
