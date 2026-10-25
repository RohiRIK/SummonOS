import Foundation
import Testing
@testable import SummonCore

@Suite("Live Mac events: only crossings are logged")
struct MacEventsTests {
    static func mac(online: Bool = true, vpn: Bool = false, freeGB: Int = 300, battery: Int? = 80, charging: Bool = false,
                    thermal: String = "nominal", displays: Int = 1) -> MacContext {
        var context = MacContextTests.sample
        context.network = .init(online: online, primaryInterface: online ? "en0" : nil, vpn: vpn)
        context.storage = [.init(name: "Macintosh HD", path: "/", freeGB: freeGB, totalGB: 994)]
        context.power = .init(battery: battery, charging: charging, onAC: charging, lowPowerMode: false, thermal: thermal)
        context.displays = Array(repeating: .init(width: 1728, height: 1117, scale: 2, main: true), count: displays)
        return context
    }

    static func titles(_ old: MacContext?, _ new: MacContext) -> [String] { MacEvents.changes(from: old, to: new).map(\.title) }

    @Test func firstLookAndNoChangeLogNothing() {
        #expect(Self.titles(nil, Self.mac()).isEmpty)
        #expect(Self.titles(Self.mac(), Self.mac()).isEmpty)
    }

    @Test func networkAndVPN() {
        #expect(Self.titles(Self.mac(), Self.mac(online: false)) == ["Network went offline"])
        #expect(Self.titles(Self.mac(online: false), Self.mac()) == ["Back online via en0"])
        #expect(Self.titles(Self.mac(), Self.mac(vpn: true)) == ["VPN connected"])
    }

    @Test func diskOnlyWhenCrossingTheLine() {
        #expect(Self.titles(Self.mac(freeGB: 25), Self.mac(freeGB: 12)) == ["Low disk space: 12 GB free on Macintosh HD"])
        #expect(Self.titles(Self.mac(freeGB: 12), Self.mac(freeGB: 8)).isEmpty)
        #expect(Self.titles(Self.mac(freeGB: 8), Self.mac(freeGB: 40)) == ["Disk space OK again: 40 GB free on Macintosh HD"])
    }

    @Test func batteryThermalAndDisplays() {
        #expect(Self.titles(Self.mac(battery: 25), Self.mac(battery: 18)) == ["Battery low (18%)"])
        #expect(Self.titles(Self.mac(battery: 15), Self.mac(battery: 9)) == ["Battery very low (9%)"])
        #expect(Self.titles(Self.mac(battery: 25), Self.mac(battery: 18, charging: true)).isEmpty)
        #expect(Self.titles(Self.mac(battery: nil), Self.mac(battery: nil)).isEmpty)
        #expect(Self.titles(Self.mac(), Self.mac(thermal: "serious")) == ["Mac is running hot (thermal serious)"])
        #expect(Self.titles(Self.mac(thermal: "critical"), Self.mac(thermal: "fair")) == ["Mac cooled down (thermal fair)"])
        #expect(Self.titles(Self.mac(), Self.mac(displays: 2)) == ["Display connected (2 now)"])
    }

    @Test func eventsAreMacKindsInTheMacCategory() {
        let events = MacEvents.changes(from: Self.mac(), to: Self.mac(online: false))
        #expect(events.first?.kind == "mac.network")
        #expect(ActivityFeed.event(from: events[0]).category == .mac)
    }
}
