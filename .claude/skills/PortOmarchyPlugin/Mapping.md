# Linux / Omarchy to macOS mapping

Grow this table every port. Verify a row on a real Mac before adding it.

## Omarchy concepts

| Omarchy | macOS |
|---|---|
| `manifest.json` (id, name, version) | `Info.plist` (`CFBundleIdentifier`, `CFBundleName`, `CFBundleShortVersionString`) |
| `kinds: bar-widget` | `MenuBarExtra` in a SwiftUI `App`, `LSUIElement=true` (no Dock icon) |
| `Panel.qml` popup | `MenuBarExtra { } .menuBarExtraStyle(.window)` |
| `PanelToolTip` | `.help("...")` |
| `Process { command: [...] }` | `Foundation.Process` or a native framework call (prefer native) |
| `Timer { interval: ... }` | `.task { while !Task.isCancelled { ...; try await Task.sleep(for:) } }` |
| `Keys.onPressed` | `.onKeyPress(...)` (macOS 14) or `.keyboardShortcut(...)` on buttons |
| `omarchy plugin add/remove` | drag `.app` to `/Applications`; login item via `SMAppService.mainApp` |
| `omarchy-launch-floating-terminal...` | `NSWorkspace.shared.open(URL)` or a SwiftUI `Window` scene |

## Networking

| Linux | macOS |
|---|---|
| `nmcli connection show` (profiles) | `networksetup -listallnetworkservices` (services: "Wi-Fi", "Ethernet", ...) |
| `nmcli connection show --active` | `SCDynamicStore` primary service, or `route -n get default` for the interface |
| `nmcli ... ipv4.method auto` | `networksetup -setdhcp "<service>"` |
| `nmcli ... ipv4.method manual ipv4.addresses A/24 ipv4.gateway G` | `networksetup -setmanual "<service>" A 255.255.255.0 G` (prefix to mask) |
| `nmcli ... ipv4.dns "a,b"` | `networksetup -setdnsservers "<service>" a b` (`Empty` clears) |
| `IP4.ADDRESS`, `IP4.GATEWAY` | `networksetup -getinfo "<service>"` or `getifaddrs` |
| `IP4.DNS` | `networksetup -getdnsservers "<service>"` |
| Wi-Fi scan (`Quickshell.Networking`, `nmcli dev wifi`) | CoreWLAN `CWWiFiClient.shared().interface()?.scanForNetworks(withName: nil)` |
| Wi-Fi connect with passphrase (stdin) | `CWInterface.associate(to:password:)` in-process |
| Forget network | `networksetup -removepreferredwirelessnetwork <iface> <ssid>` (admin) |
| Wi-Fi on/off | `CWInterface.setPower(_:)` |
| `iw` link: signal, bitrate, freq | `CWInterface.rssiValue()`, `transmitRate()`, `wlanChannel()` |
| `omarchy-network-band` (read) | `CWInterface.wlanChannel()?.channelBand` |
| `omarchy-network-band <band>` (set) | no API. Drop. |
| rx/tx byte counters | `getifaddrs` + `if_data.ifi_ibytes` / `ifi_obytes` |
| `ping` | `/sbin/ping -c 1 -t 2 <host>` (same flags differ from Linux: `-t` is timeout) |
| `ip addr` | `ifconfig`, or `getifaddrs` in code |

## Permissions

| Need | macOS requirement |
|---|---|
| SSID/BSSID | Location Services auth (`CLLocationManager`) + `NSLocationUsageDescription` in Info.plist |
| Change network settings | admin via `osascript`: pass values as argv after `--`, build the command with `quoted form of` (see mac-network `Shell.swift`). Never splice values into script text. |
| Outbound HTTP | none for a non-sandboxed app |

## Verified quirks

| Quirk | Detail |
|---|---|
| `networksetup -getairportnetwork en0` | says "You are not associated with an AirPort network." while connected (macOS 15+ privacy). Use CoreWLAN + Location. |
| `networksetup -setmanual` | router argument is required; one IPv4 address per service (no comma list). |
| `networksetup` errors | printed on stdout as `** Error: ...`, exit 4. Read stdout for the message. |
| `osascript -e ... args` | args starting with `-` are read as osascript flags. Put `--` before argv. |
| `do shell script` result | converts `\n` to `\r`. Split on any newline. |
| User cancels admin prompt | osascript fails with `User canceled. (-128)`. |
| DHCP-provided DNS | `ipconfig getoption <device> domain_name_server` (first server only). |
| Default-route interface | `route -n get default`, line `interface: en0`. |
| Join a saved Wi-Fi network | CoreWLAN `associate(password: nil)` cannot read the system keychain; use `networksetup -setairportnetwork <dev> <ssid>` (no password: uses saved one). Reports failure on stdout with exit 0. |
| Join a new network with password | CoreWLAN `associate(to:password:)` in-process. Never `networksetup ... <password>`: argv is visible in `ps`. |
| Agent skills (Omarchy `default/agents/skills` → `~/.agents`, `~/.claude`, `~/.codex`, `~/.gemini/config` skill dirs) | Same symlink loop (`summon skills link`). Antigravity CLI reads only `~/.gemini/config/skills`, not `~/.antigravity` (editor extensions) or `~/.gemini/skills`. OpenCode reads `~/.claude/skills` and `~/.agents/skills`: one skill in both logs "duplicate skill name" but works. |
