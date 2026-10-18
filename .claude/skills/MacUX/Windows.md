# Windows: the full-size companion to a menu bar app

A plugin's main window (Activity, history, library) must look like Mail or System Settings on the
user's OS, not like a web page. The way to get there is to **use system containers and draw almost
nothing yourself**; Apple restyled them between macOS 26 Tahoe and 27 Golden Gate, and hand-drawn chrome
broke both times. Research and sources: `docs/research/2026-10-18-mac-gui-design/02-…` and `03-…`.

## Anatomy (top to bottom, leading to trailing)

1. **Unified toolbar.** Window title < 15 characters, never the app name (or none when content titles
   itself). At most **3 toolbar groups** (`ToolbarItemGroup`, `ToolbarSpacer` on 26+). Monochrome outline
   SF Symbols; never a text button grouped with a symbol button. **One** prominent primary action, trailing.
   Status text in the toolbar gets `.sharedBackgroundVisibility(.hidden)` (26+) so it does not read as a
   button. Every toolbar command also exists in the menu bar (`CommandMenu`) with a shortcut.
2. **Sidebar** (`NavigationSplitView`), at most 2 levels, SF Symbols in the accent colour, fixed colour only
   when colour means something. Hideable (toolbar button + ⌃⌘S). No material or `NSVisualEffectView` of your own.
3. **Content** column: `List` / `Table` with system selection. Runs under the toolbar; separation comes from the
   system scroll edge effect, not a divider or a background you draw.
4. **Inspector** (trailing): `.inspector(isPresented:)` + `.inspectorColumnWidth(min:ideal:max:)` for detail
   of the selection. Better than a third split column for "details of one row".
5. **Bottom bar**, optional: non-critical window facts only (counts, "Updated 2 min ago"), like Finder's
   status bar. Never critical controls.

Search: `.searchable` on the `NavigationSplitView` puts it in the trailing toolbar (Mail). Use
`placement: .sidebar` only when it filters the sidebar itself (System Settings). Default to broad scope;
narrow with tokens (`searchable(text:tokens:)`) or a scope control.

## Layers and glass

- Liquid Glass is the **control and navigation layer** only (toolbar, sidebar, floating controls). Content
  (rows, cards, detail) uses semantic backgrounds or `Material`. Never glass on glass.
- Custom glass: `if #available(macOS 26, *)` with a `Material` fallback, behind one helper per concept
  (`panelSurface()`, `primaryActionStyle()`), and several nearby glass shapes in one `GlassEffectContainer`.
- No custom bar backgrounds, gradients or dividers under the toolbar. One scroll edge style per scroll view;
  `.scrollEdgeEffectStyle(.hard, for: .top)` only for pinned headers or dense text.
- Corners: inner shapes concentric (`ConcentricRectangle`, `.containerShape`) or capsules; no hard-coded radius
  on anything touching a window edge. No hard-coded control heights: `.controlSize` (26 made controls taller).
- Inactive window: custom chrome reads `@Environment(\.appearsActive)` and dims.

## Status without a dashboard

A row of rounded tiles with big numbers is the #1 cause of "looks like a web admin page". Instead:
window subtitle (`.navigationSubtitle`), a toolbar status item, a bottom strip, or one grouped `Form`
section with one line per fact (symbol, label, value, optional fix button). Problems appear only when
there are any. Details in `ActivityFeeds.md`.

## Opening the window from a menu bar (accessory) app

Since macOS 14 activation is cooperative: `NSApp.activate()` is a request, and an accessory app's new
window opens **behind** the frontmost app (Apple calls this intended). Opening from a URL scheme loses the
handed-over activation if the window is built late. Recipe, all four steps:

```swift
@MainActor func showWindow(_ id: String, _ openWindow: OpenWindowAction) {
    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }  // Dock icon + ⌘Tab
    NSApp.activate()
    openWindow(id: id)          // only brings a *reused* window forward
}
// In the window's root view: raise once the NSWindow exists (a new window is built a run loop later).
.background(WindowAccessor { window in
    window.makeKeyAndOrderFront(nil)
    if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true); window.orderFrontRegardless() }  // deprecated fallback
})
```

`WindowAccessor` is an `NSViewRepresentable` whose view calls back from `viewDidMoveToWindow` (code in the
mechanics report §3.2). Then:

- Back to `.accessory` only after the last regular window closes (`onDisappear` + check other visible
  titled windows). Switching while a window is visible sends it to the back.
- `.defaultLaunchBehavior(.suppressed)` on every `Window` scene of a menu bar app (no ghost window at launch
  or restore). Never call `setActivationPolicy` in `App.init()` (NSApp is nil); `LSUIElement` sets the launch state.
- While `.regular` the app shows a main menu: give it at least About, Settings… and Quit (`CommandGroup`).
- Settings: `openSettings` is a no-op on 26 without a live SwiftUI view and `SettingsLink` is unreliable in
  `MenuBarExtra`. Either declare a hidden 1×1 `Window` **before** the `Settings` scene and call
  `openSettings` from it, or make Settings a plain `Window(id: "settings")` with the recipe above and
  `CommandGroup(replacing: .appSettings)` for ⌘,.

## Useful chrome APIs (macOS 15 unless marked)

`.toolbar(removing: .title)`, `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`,
`.containerBackground(.thinMaterial, for: .window)`, `.windowBackgroundDragBehavior(.enabled)`,
`.windowResizability(.contentSize)`, `.defaultWindowPlacement`, `.restorationBehavior(.disabled)` (utility and
onboarding windows), `.windowLevel(.floating)` (always-on-top companions only).
26+: `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass / .glassProminent)`, `ToolbarSpacer`,
`.sharedBackgroundVisibility`, `.scrollEdgeEffectStyle`, `.safeAreaBar`, `.backgroundExtensionEffect`.
27: `.labelStyle(.titleAndIcon)` to opt a menu item into an icon (menus default to minimal icons).
