---
name: MacAppBuild
description: "Scaffold, build, bundle, preview, verify, and release a native SwiftUI macOS app with SwiftPM and Xcode MCP. USE WHEN creating a new macOS plugin, building or testing it, rendering previews, checking a change before a PR, fixing build/bundle/signing problems, or releasing an .app. NOT FOR app structure or backend calls (use MacAppArchitecture), view design (use MacUX), or porting a Linux widget (use PortOmarchyPlugin)."
category: reference
effort: medium
domain: dev
---

# MacAppBuild

SwiftPM-only build, verify and ship loop. No Xcode project; Xcode is used through MCP for previews.

## Quick Reference

- Layout, `Package.swift`, `App.swift`, `Info.plist`, `bundle.sh`, CI: `Scaffold.md`. Copy, then rename.
- `swift build` makes a bare binary. Only the `.app` bundle gets a proper GUI session, Info.plist keys, and permission prompts. Always test the bundle.
- **Done means verified:** follow `Verify.md` (gate, previews, run, logs, manual checklist) before claiming a change works.
- **Shipping:** `Release.md` (zip or DMG, version bump, Gatekeeper, notarization, updates).
- Xcode MCP (`.mcp.json`, server `xcode` = `xcrun mcpbridge`): open the package in Xcode first (`xed plugins/<name>`), then use `BuildProject`, `RunAllTests`, `RenderPreview` (UI snapshot as image), `GetConsoleOutput`. CLI scripts stay the source of truth for CI.
- Previews need the views in a **library** target with a library product (`MacNetworkUI`); executable targets fail with `DebugDylibNotEnabled`. Keep `@main` alone in the executable.
- `RenderPreview` sometimes fails right after a rebuild (Xcode still compiling). `render-previews.sh` retries once.
- Background sessions do not load the `xcode` MCP tools. Use `bun tools/xcode-mcp.ts <Tool> <json>` and `tools/render-previews.sh <plugin> <UITarget>`. First use per folder needs `XcodeOpenWorkspace` + the user clicking Allow in Xcode.

## Gotchas

- `LSUIElement=true` hides the Dock icon. Without it the menu bar app also shows in the Dock and Cmd-Tab.
- Permission usage strings (`NSLocationUsageDescription`, etc.) only work from the bundle's Info.plist. A bare `swift run` binary never gets the prompt.
- Ad-hoc signing (`codesign -s -`) runs locally. Other Macs block it via Gatekeeper; they need right-click > Open, or a Developer ID + notarization.
- TCC ties permissions to the code signature. A plain ad-hoc signature is a cdhash that changes every build, so grants (Calendars, Reminders, Location) vanish after a rebuild. Sign with `codesign -s - -r='designated => identifier "<bundle-id>"'` so rebuilds keep grants (mac-calendar `scripts/bundle.sh`). Reset with `tccutil reset All <bundle-id>` to retest first-run.
- `swift run` of a SwiftUI `App` may show no window or menu item. Test through `open <App>.app`.
- A menu bar app with `.window` style gets no Esc-to-close by default. Handle `.onKeyPress(.escape)` and dismiss.
- `Process` with `waitUntilExit()` on the main actor freezes the menu. Run commands off-main (`Task.detached` or an actor).
- Never let SwiftPM write `.build/` inside Google Drive (461 MB for a hello-world app). Both scripts pass `--scratch-path ~/Library/Caches/macplugins/<name>`. Do not run bare `swift build` in a plugin folder.
- Bun `Bun.spawn` stdin is buffered: call `proc.stdin.flush()` after each write, or an MCP server never sees the request. Send `tools/call` only after the `initialize` reply.
- Cloud (Linux) sessions have no Swift, and download.swift.org is blocked. Docker Hub works: fetch the `swift:6.4-noble` manifest, download the ~1.1 GB toolchain layer (the largest blob) with a registry token, check its sha256, `tar -xzf` it into `/opt/swift`, and `apt-get install libcurl4-openssl-dev libxml2-dev libsqlite3-dev libz3-dev libncurses-dev`. Docker Hub rate-limits manifest requests, and ECR Public's blob CDN is blocked. Only Foundation-only Core targets build there; keep AppKit/SwiftUI behind `#if os(macOS)` in `Package.swift` (mac-assistant).
- Command Line Tools only (no Xcode): `swift test` fails with "no such module 'Testing'". CLT ships `Testing.framework` off the search path. Always run tests via `scripts/test.sh`, which adds the `-F`/rpath flags.

## Examples

**Example 1: New plugin**
```
User: "make a menu bar app that shows my battery cycles"
→ copy Scaffold.md files into plugins/battery-cycles/, rename, scripts/test.sh, scripts/bundle.sh, open .app
```
