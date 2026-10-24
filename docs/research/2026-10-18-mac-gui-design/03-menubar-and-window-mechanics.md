---
type: Research
title: Menu bar and window mechanics
description: Swift 6 and SwiftUI mechanics for polished menu bar apps and companion windows on macOS 15 and 26.
tags: [research, swiftui, menubar]
created: 2026-10-18
---

# 03 — Mechanics: polished menu bar apps and companion windows (Swift 6 / SwiftUI, macOS 15 and 26)

Research date: 2026-10-18. Target: minimum macOS 15, Liquid Glass behind `if #available(macOS 26, *)`.
Confidence: **[doc]** = Apple documentation, **[forum]** = Apple forums / DTS, **[blog]** = third-party write-up,
**[inferred]** = my synthesis, not verified on hardware in this pass.

---

## 0. What SummonOS chose, and which requirement decided it (2026-10-24)

Summon moved from `MenuBarExtra(.window)` to `NSStatusItem` + a nonactivating `NSPanel`
(`incubator/summon/Sources/SummonMenuUI/StatusPanel.swift`, spec `incubator/summon/docs/menubar-panel.md`). Per
requirement:

| Requirement | What decided it |
|---|---|
| Keyboard access | ⌃⌥Space must open the panel. `MenuBarExtra` has no open/close API, so a hotkey can't show it. Inside the panel: arrows, Return, ←/→, Esc, ⌘, and ⌘Q. |
| Focus while another app is active | Typing into the search field must not take the other app's menu bar or focus. `.nonactivatingPanel` + `canBecomeKey` makes the panel key without activating Summon. Because typing can then land by accident, Return is ignored for 300 ms after a non-click open (`PanelOpenGuard`). |
| Window ordering | `.statusBar` level + `.fullScreenAuxiliary` + `.canJoinAllSpaces`: over fullscreen apps, on every Space. Settings and Activity are normal windows opened after `NSApp.activate()`, so they don't open behind other apps. |
| Live content | The panel refreshes every second while open (agent clock, Activity) and resizes once per change with the top edge pinned. Since 2026-10-24 the status item label is live too, with the panel closed. |

Not a reason: `MenuBarExtra` isn't broken. Workspace plugins whose panel is click-only keep it
(`examples/menubar-starter`); `examples/menubar-panel-starter` is the AppKit version for the rest.

Verified on macOS 26.x only. macOS 15 compiles but its runtime is unchecked; macOS 27 betas break the persistent
button highlight (FB23330269, section 1.4).

## 1. MenuBarExtra(.window) vs NSStatusItem + custom NSPanel

### 1.1 What `MenuBarExtra(.window)` gives you and where it stops

`MenuBarExtra { … }.menuBarExtraStyle(.window)` hosts SwiftUI in a borderless panel under the status item. You get
outside-click dismissal, a status item highlight, and sizing to the content's ideal size for free. The default
`.menu` style turns content into `NSMenu` items, so `HStack`s become stacked rows and frames are ignored
(Paul Contreras hit this). **[blog]**

Limits (macOS 13 to 26), which is why serious apps move off it:

| Need | MenuBarExtra | Workaround |
|---|---|---|
| Open/close from code (hotkey, URL, after an action) | No binding; only `isInserted:` (show/hide the *icon*) | `MenuBarExtraAccess` (orchetect): `.menuBarExtraAccess(isPresented:)`, plus `{ statusItem in … }` to reach the `NSStatusItem` |
| Right-click menu distinct from left-click panel | No | Need the `NSStatusItem` (MenuBarExtraAccess or AppKit) |
| Panel position, arrow, offset, animation | None | Custom `NSPanel` |
| Live, variable-width label (text + icon + badge) | The label is re-rendered as an image; limited, and animation is not supported | `NSStatusItem` + `NSHostingView` |
| `openSettings` / `SettingsLink` inside it | Unreliable (no window context, app not active) | See section 3 |
| `ColorPicker`, `NSColorPanel`, `NSOpenPanel` | These auxiliary panels open behind other apps | Avoid them, or activate the app first (section 3) |
| Animated resize when content changes | Jumps | Custom panel with `setFrame(_:display:animate:)` |

`MenuBarExtraAccess` hooks the private window and status item. It is a dependency, which AGENTS.md forbids unless a
skill allows it, so treat it as a reference implementation and write the ~150-line AppKit version below.
FluidMenuBarExtra (lfroms) is the other reference: an `NSWindow`-based extra with animated resize, fade-out on
dismiss, screen-edge clamping and a persistent highlight. **[blog]**

Rule: **stay on `MenuBarExtra(.window)` when the panel is static and opened only by clicking. Switch to
`NSStatusItem` + `NSPanel` once you need any of these: programmatic open, right-click menu, live label, animated
resize, or a text field that must reliably take keystrokes.**

### 1.2 The custom panel

```swift
import AppKit
import SwiftUI

final class StatusPanel: NSPanel {
    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(contentRect: .zero,
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar                // .popUpMenu covers menus; .floating sits under full-screen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false         // a nonactivating panel's app is often not active; manage dismissal yourself
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let host = NSHostingView(rootView: content()
            .background(.regularMaterial, in: .rect(cornerRadius: 12)))   // or glass on 26, see section 5
        host.sizingOptions = [.preferredContentSize]   // macOS 13+: host follows SwiftUI's ideal size
        contentView = host
    }

    // A borderless panel refuses key status by default, so text fields would never get keystrokes.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Escape closes, as a menu does
    override func cancelOperation(_ sender: Any?) { close() }
}
```

`.nonactivatingPanel` lets the panel become **key** (it takes keystrokes) without activating the app, so the
frontmost app keeps its menu bar and focus. This is how Spotlight and Raycast feel. The style mask must be set at
init: changing `.nonactivatingPanel` later is unreliable on older systems. **[inferred, well known]**

### 1.3 Positioning under the status item

```swift
@MainActor
func position(_ panel: NSPanel, under button: NSStatusBarButton, gap: CGFloat = 4) {
    guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
    let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let size = panel.frame.size
    let visible = screen.visibleFrame                 // excludes menu bar and Dock
    var x = anchor.midX - size.width / 2              // centered; use anchor.minX for left alignment as Control Center does
    x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
    let y = anchor.minY - size.height - gap
    panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
}
```

Use `button.window?.screen`, not `NSScreen.main`: with several displays the status item lives on the screen
whose menu bar was clicked. Recompute on every open; `NSApplication.didChangeScreenParametersNotification` only
invalidates. **[blog: fazm.ai]**

### 1.4 Opening, animating, closing on outside click

```swift
@MainActor
final class PanelController {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let panel: StatusPanel
    private var monitors: [Any] = []

    init(panel: StatusPanel) { self.panel = panel }

    func toggle() { panel.isVisible ? close() : open() }

    func open() {
        guard let button = statusItem.button else { return }
        panel.layoutIfNeeded()
        position(panel, under: button)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)       // the panel is nonactivating, so this does not activate the app
        button.highlight(true)                // persistent highlight while open (see macOS 27 note below)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // Clicks in other apps: global monitor. It never sees our own events.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        } as Any)
        // Losing key status (Cmd-Tab, clicking the desktop, another of our windows)
        monitors.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    func close() {
        monitors.forEach { m in
            if let token = m as? NSObjectProtocol { NotificationCenter.default.removeObserver(token) }
            else { NSEvent.removeMonitor(m) }
        }
        monitors.removeAll()
        statusItem.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; panel.animator().alphaValue = 0 },
                                             completionHandler: { [panel] in MainActor.assumeIsolated { panel.orderOut(nil) } })
    }
}
```

Notes:
- A click on the status item itself also fires the global monitor on some systems and then toggles, so the panel
  closes and reopens. Ignore global clicks inside `button.window?.frame`, or debounce by timestamp. **[inferred]**
- On macOS 27 betas (FB23330269), `button.highlight(true)` no longer sticks. DTS pointed at the new
  `expandedInterfaceDelegate` for user-initiated opens; there is no fix yet for programmatic highlights.
  On the same betas, global taps outside a custom NSWindow/NSPanel were reported as undetectable (FB23688090).
  Keep `didResignKey` as the second line of dismissal. **[forum 836113]**
- For animated resize when content changes, observe the hosting view's `fittingSize` and call
  `panel.setFrame(newFrame, display: true, animate: true)`, keeping the top edge pinned (y = anchor.minY - height). **[inferred]**

### 1.5 Keyboard focus in a panel

- `canBecomeKey == true` + `makeKeyAndOrderFront` is required for `TextField` input. With
  `becomesKeyOnlyIfNeeded = true` the panel becomes key only when a control needs it; call `makeKey()` explicitly
  when you want ⌘F-style typing immediately. **[blog: fazm.ai]**
- In SwiftUI, use `@FocusState` + `.defaultFocus($focus, .search)` (macOS 13+) or set focus in `.onAppear`
  *after* the window is key; setting it before `makeKey` is dropped. Use `.onKeyPress` (macOS 14+) for arrow keys and
  return in lists. Add `.focusable()` + `.focusEffectDisabled()` on custom rows. **[inferred]**
- Shortcuts such as ⌘, and ⌘Q in a panel footer only fire while the panel is key, because an accessory app has no
  main menu in the menu bar. Add them with `.keyboardShortcut` on the buttons. **[inferred]**

### 1.6 Sizing to content

`NSHostingView.sizingOptions = [.preferredContentSize]` (or `.intrinsicContentSize`) plus a fixed width on the
SwiftUI root (`.frame(width: 340)`) and `.fixedSize(horizontal: false, vertical: true)` gives height-to-content.
Cap height with `.frame(maxHeight: screen.visibleFrame.height - 40)` and put long lists in a `ScrollView`.
`NSHostingController` + `preferredContentSize` is the equivalent if you use `contentViewController`.

---

## 2. Status item live content

### 2.1 Template images (the baseline)

```swift
let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "CPU")!
    .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))!
image.isTemplate = true                     // tints for light/dark/tinted menu bar and the "inactive" dimming
statusItem.button?.image = image
statusItem.button?.imagePosition = .imageLeading
statusItem.button?.title = "42%"            // text next to the icon, uses menu bar font automatically
statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
```

Monospaced digits stop the width from jittering every second. Non-template colored images are acceptable only for
state such as recording red, which menu bar HIG allows sparingly.

### 2.2 SwiftUI inside the status item

Two approaches:

**A. Render to an image (robust, cheap).** `ImageRenderer` (macOS 13+) turns a SwiftUI label into an `NSImage`;
mark it template if it is monochrome.

```swift
@MainActor
func renderLabel(_ view: some View) -> NSImage? {
    let r = ImageRenderer(content: view.foregroundStyle(.black))   // black + template = system tint
    r.scale = NSScreen.main?.backingScaleFactor ?? 2
    guard let img = r.nsImage else { return nil }
    img.isTemplate = true
    return img
}
```

**B. Host a live `NSHostingView` in `button` (interactive, animatable, more fragile).** `NSStatusItem.view` is
deprecated (10.14); add the hosting view as a subview of `button`. Report the SwiftUI size through a preference
key or `sizingOptions`, then set `statusItem.length` (height is fixed at the menu bar's ~22–24 pt). Multi.app used a
`GeometryReader` + `PreferenceKey` → `statusItem.length` pipeline and found it more reliable than Auto Layout.
**[blog: multi.app]**

```swift
let host = NSHostingView(rootView: LiveLabel(model: model))
host.translatesAutoresizingMaskIntoConstraints = false
statusItem.button?.addSubview(host)
NSLayoutConstraint.activate([
    host.leadingAnchor.constraint(equalTo: statusItem.button!.leadingAnchor),
    host.trailingAnchor.constraint(equalTo: statusItem.button!.trailingAnchor),
    host.centerYAnchor.constraint(equalTo: statusItem.button!.centerYAnchor),
])
// when SwiftUI reports a new width:
statusItem.length = max(22, measuredWidth + 8)
```

Caveats: a hosted view does not get the automatic template tint or the dimmed look on an inactive display, so use
`.foregroundStyle(.primary)` and handle `controlActiveState`. The pressed highlight comes from the button, so keep
`button.target/action` and set `host.allowedTouchTypes`/hit-testing off, or forward clicks. On **macOS 26**,
SwiftUI animations inside a status-item `NSHostingView` are reported as choppy (forum 803501, unanswered). For
animated labels prefer approach A with a timer, or Core Animation layers. **[forum]**

### 2.3 Badges

Draw the badge into the image (approach A: `ZStack(alignment: .topTrailing)` with a small `Circle`), or use a
template icon + a separate non-template dot. A template image cannot carry a colored badge; that part must
be non-template, or the whole image must be. The common trick is two status-bar subviews: a template image view
and a colored `CALayer` dot. **[inferred]**

### 2.4 Animating the icon (SF Symbol effects)

`NSStatusBarButton` has no `addSymbolEffect`. `NSImageView.addSymbolEffect(_:options:animated:)` (macOS 14+) does.
The forum answer: add an `NSImageView` as a subview of the button and animate that. The trade-off is that it
does not dim with the button's inactive state the way `button.image` does. **[forum 747451]**

```swift
let iv = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Syncing")!)
iv.contentTintColor = .labelColor
iv.frame = button.bounds
iv.autoresizingMask = [.width, .height]
button.image = nil
button.addSubview(iv)
iv.addSymbolEffect(.rotate, options: .repeat(.continuous))          // macOS 15 rotate; .pulse/.bounce on 14
// stop:
iv.removeAllSymbolEffects()
// swap glyph with a transition (macOS 14+):
iv.setSymbolImage(NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Synced")!,
                  contentTransition: .replace)
```

Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, and do not animate continuously while idle, because
the menu bar is shared and continuous motion is distracting and costs energy.

### 2.5 Left-click panel, right-click menu

Do **not** assign `statusItem.menu` (it takes over every click). Route by event type:

```swift
button.target = self
button.action = #selector(statusItemClicked(_:))
button.sendAction(on: [.leftMouseUp, .rightMouseUp])

@objc func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    if isRight {
        statusItem.menu = contextMenu            // attach temporarily…
        statusItem.button?.performClick(nil)     // …show it at the item, natively positioned
        statusItem.menu = nil                    // detach so left click goes back to the panel
    } else {
        panelController.toggle()
    }
}
```

`performClick` with a temporarily attached menu keeps native menu placement and highlight. The alternative
`menu.popUp(positioning:at:in:)` works but places the menu slightly differently. **[inferred, common pattern]**

---

## 3. Opening a regular window from an LSUIElement / accessory app so it comes to the FRONT

### 3.1 Why our Window opened behind other apps

Since macOS 14, activation is **cooperative**: `NSApp.activate()` is a *request*, and "the system dynamically
determines whether to grant activation state based on the context." Only the active app can yield to another.
`activate(ignoringOtherApps:)` is deprecated in 14 for this reason. **[doc]** An accessory app (no Dock
icon) is in the weakest position. Apple DTS confirmed on the forums that `NSApp.activate()` in a menu bar app
leaves a newly opened window *behind* the frontmost app. That is the intended behavior, meant to stop focus
stealing. The recommended answer was "let `openWindow` handle activation" (stated as untested). Several developers report
that neither `openWindow` nor switching the activation policy alone fixed it, and fell back to the deprecated call.
FB23508310 and FB23519126 are open. **[forum 836619]**

The URL-scheme case is different. When *another* app (or Terminal `open`) opens our URL, `NSWorkspace`
"automatically handles" the yield, so a URL open from the frontmost app *should* grant activation. **[doc]**
It still fails when (a) the handler opens the window asynchronously after the activation token is spent, or
(b) the SwiftUI `Window` is created fresh: Apple documents that `openWindow` only brings a window forward when it *reuses*
an existing one, and a newly built window can be ordered behind (TablePro PR #2019). **[blog]** One forum user
noted that opening your *own* deep link via `NSWorkspace.shared.open(URL(string: "myapp://main")!)` is a
workaround that does activate the app. **[forum 836619]**

### 3.2 The reliable recipe (combine all three)

```swift
@MainActor
enum WindowRaiser {
    /// Call from MenuBarExtra buttons, URL handlers (`.onOpenURL` / application(_:open:)), hotkeys.
    static func show(id: String, openWindow: OpenWindowAction) {
        // 1. Become a regular app for as long as the window is open: Dock icon, menu bar, Cmd-Tab entry.
        //    The system grants activation to regular apps far more readily than to accessory ones.
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        // 2. Request activation (cooperative). Keep the deprecated call as a fallback; it still works on 15/26.
        NSApp.activate()
        // 3. Open or reuse the SwiftUI window.
        openWindow(id: id)
        // 4. Order it front once it exists (a new window is built on the next runloop turn).
        Task { @MainActor in
            await Task.yield()
            if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == id }) {
                w.makeKeyAndOrderFront(nil)
                if !NSApp.isActive {                      // activation refused: fall back
                    NSApp.activate(ignoringOtherApps: true)   // deprecated, still functional
                    w.orderFrontRegardless()
                }
            }
        }
    }
}
```

SwiftUI `Window(id:)` windows get `identifier` = the scene id plus a suffix on some versions, so match with
`hasPrefix(id)`. Better: **self-raise from inside the window** so you never have to search:

```swift
struct WindowAccessor: NSViewRepresentable {        // put in .background() of the window's root view
    let onWindow: @MainActor (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { Raiser(onWindow: onWindow) }
    func updateNSView(_ v: NSView, context: Context) {}
    final class Raiser: NSView {
        let onWindow: @MainActor (NSWindow) -> Void
        init(onWindow: @escaping @MainActor (NSWindow) -> Void) { self.onWindow = onWindow; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindow(window)
        }
    }
}

// Usage
Window("Summon", id: "main") {
    MainView()
        .background(WindowAccessor { w in
            NSApp.activate()
            w.makeKeyAndOrderFront(nil)
        })
}
```

This is TablePro's fix: raise in `viewDidMoveToWindow` and sequence `openWindow` after any sheet has dismissed.
Avoid `orderFrontRegardless` + delays as the *primary* fix; keep them as the last fallback. **[blog]**

### 3.3 Dock icon only while the window is open

```swift
// On close: back to accessory (no Dock icon). Use a delegate or SwiftUI .onDisappear.
.onDisappear {
    // Do not drop to .accessory while another regular window (Settings, About) is still visible.
    let others = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) && $0.identifier?.rawValue != "main" }
    if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
}
```

Gotchas: switching to `.accessory` while the window is up sends it behind other apps immediately; a 5 s delayed
switch did the same. **[forum 836619]** Do not call `setActivationPolicy` in `App.init()`: `NSApp` is
nil there and it crashes. Use `LSUIElement = YES` (`INFOPLIST_KEY_LSUIElement`) for the launch state. **[blog]**
After switching to `.regular`, the main menu appears; give it at least an App menu (About, Settings…, Quit) with
`CommandGroup`, or it looks broken.

### 3.4 Settings window specifically

`SettingsLink` is unreliable inside `MenuBarExtra`. `@Environment(\.openSettings)` needs a live render tree:
steipete found it works on 15 but is a no-op on 26 without one. Private `showSettingsWindow:` broke in 14.
The working pattern: declare a 1×1 hidden `Window` scene **before** the `Settings` scene (scene order matters on
15.5), keep `openSettings` in that hidden view, and on request run `.regular` → 100 ms → activate →
`openSettings()` → 200 ms → find window (`identifier == "com.apple.SwiftUI.Settings"`) →
`makeKeyAndOrderFront` + `orderFrontRegardless`. Revert to `.accessory` in `Settings { … }.onDisappear`.
VibeTunnel's `SettingsOpener.swift` is the production version. **[blog: steipete]** A simpler alternative that
avoids the hidden window: make Settings a normal `Window("Settings", id: "settings")` scene and use the 3.2 recipe;
bind ⌘, with `CommandGroup(replacing: .appSettings)`. **[inferred]**

---

## 4. Window chrome (macOS 15 APIs unless marked)

```swift
Window("Summon", id: "main") {
    ContentView()
        .toolbar(removing: .title)                                   // 15: keep traffic lights, drop title text
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)   // 15: content runs under the titlebar
        .containerBackground(.thinMaterial, for: .window)            // 15: translucent window background
        .windowMinimizeBehavior(.disabled)                           // 15: utility windows
}
.windowStyle(.hiddenTitleBar)          // 13: removes title + toolbar background together
.windowBackgroundDragBehavior(.enabled) // 15: drag from any empty background
.windowResizability(.contentSize)       // 13: min/max follow the content's frame
.defaultSize(width: 520, height: 380)
.defaultWindowPlacement { content, context in   // 15
    let size = content.sizeThatFits(.unspecified)
    return WindowPlacement(.center, size: size)
}
.restorationBehavior(.disabled)         // 15: utility/onboarding windows should not restore
.windowLevel(.floating)                 // 15: optional, for an always-on-top companion
.defaultLaunchBehavior(.suppressed)     // 15: do not open at launch for a menu bar app
```

Sources: nilcoalescing (containerBackground / toolbar(removing:) / windowBackgroundDragBehavior), WWDC24 10148
"Tailor macOS windows with SwiftUI". **[blog][doc]** `.windowStyle(.plain)` (15) gives a borderless window with no chrome;
pair it with `WindowDragGesture()` (15) on a custom handle: `.gesture(WindowDragGesture())` and
`.allowsWindowActivationEvents(true)` so the first click both activates and drags.

**`.defaultLaunchBehavior(.suppressed)` matters for us:** a `Window` scene in an LSUIElement app otherwise opens
at launch on some versions, or is restored, which looks like a ghost window.

**AppKit equivalents** (when you own the NSWindow, for example through `WindowAccessor`):

```swift
w.titlebarAppearsTransparent = true
w.titleVisibility = .hidden
w.styleMask.insert(.fullSizeContentView)
w.toolbarStyle = .unified            // .unifiedCompact for small utility windows
w.isMovableByWindowBackground = true
w.setFrameAutosaveName("SummonMain") // restores frame across launches (set before showing)
// Titlebar accessory, e.g. a trailing status pill
let acc = NSTitlebarAccessoryViewController()
acc.view = NSHostingView(rootView: StatusPill())
acc.layoutAttribute = .trailing
w.addTitlebarAccessoryViewController(acc)
```

`NSVisualEffectView` (`material = .popover/.hudWindow/.sidebar`, `blendingMode = .behindWindow`,
`state = .active`) is still the tool when you need vibrancy that stays active while the app is inactive. SwiftUI
materials follow the window's key state; a panel from a nonactivating app often looks "inactive" (flat grey) unless
you force `state = .active`. Wrap it with `NSViewRepresentable`. **[inferred, common]**

Frame restoration: SwiftUI restores `Window` frames automatically unless `.restorationBehavior(.disabled)`; for
AppKit panels use `setFrameAutosaveName`. For a panel anchored to the status item, do **not** restore its frame:
recompute.

---

## 5. macOS 26 (Liquid Glass) APIs, gated to macOS 15

All of these are macOS 26+. **[doc via skill reference]**

| API | Use |
|---|---|
| `.glassEffect(_ glass: Glass = .regular, in: some Shape = capsule)` | Glass on a custom control or panel surface. `.regular`, `.clear`, `.identity`; `.tint(_:)`, `.interactive()` |
| `GlassEffectContainer(spacing:) { … }` | Group nearby glass shapes so they blend and morph. Glass cannot sample other glass, so always group |
| `.glassEffectID(_:in:)`, `.glassEffectUnion(id:namespace:)`, `.glassEffectTransition(.materialize)` | Morphing between states |
| `.buttonStyle(.glass)`, `.glassProminent`, `.glass(.clear)` | Buttons. Prefer these to `.glassEffect(.regular.interactive())` on buttons |
| `.backgroundExtensionEffect()` | Mirrors and blurs content under sidebars or the toolbar edge (hero images in split views) |
| `.scrollEdgeEffectStyle(.soft / .hard, for: .top)` | Edge fade under the toolbar or floating bars |
| `ToolbarSpacer(.fixed / .flexible)` | Splits toolbar items into separate glass groups |

Gating pattern: keep one modifier per concept so call sites stay clean.

```swift
extension View {
    @ViewBuilder
    func panelSurface(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func primaryActionStyle() -> some View {
        if #available(macOS 26, *) { self.buttonStyle(.glassProminent) }
        else { self.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder
    func softTopEdge() -> some View {
        if #available(macOS 26, *) { self.scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }
}

// Toolbar: ToolbarSpacer is ToolbarContent, so gate inside the builder
.toolbar {
    ToolbarItem { RefreshButton() }
    if #available(macOS 26, *) { ToolbarSpacer(.fixed) }
    ToolbarItem { FilterMenu() }
}
```

Rules: glass is for the **control layer** (buttons, floating bars, the panel shell), not content rows. Do not
stack glass on glass, and do not combine `glassEffect` with `.background(.material)`. Apply it after padding,
frame and foreground modifiers. On 26 the system already gives `MenuBarExtra(.window)` panels and the
toolbar a glass treatment; adding your own glass inside creates double glass. In a custom `NSPanel` on 26 you can
use `NSGlassEffectView` (AppKit, 26) as `contentView` instead of `NSVisualEffectView`. **[inferred; verify
name in SDK]**. The `if #available` checks in `@ViewBuilder` change the view's identity per OS but not per frame,
which is fine.

---

## 6. Upside-down / garbled text (crash row program name rendered upside down)

Ranked by likelihood for "a process name in a list row shows upside down":

**1. Text drawn by Core Graphics / Core Text into a flipped context.** `CTLineDraw`, `CTFrameDraw`,
`NSAttributedString.draw` into a raw `CGContext`, or `ImageRenderer.cgImage` drawn with `context.draw(_:in:)`
inside a flipped `NSView` (`isFlipped == true`, which every SwiftUI-hosted AppKit view effectively is) produces
vertically mirrored glyphs. Fix: set `context.textMatrix = .identity` and flip the CTM explicitly, or draw through
`NSGraphicsContext(cgContext:flipped:)` with the correct flag. For images use `NSImage(size:flipped:drawingHandler:)`
with `flipped` matching the drawing code.

```swift
// Core Text in a flipped NSView
override func draw(_ dirty: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: 0, y: bounds.height)
    ctx.scaleBy(x: 1, y: -1)                 // undo the view's flip for CT only
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}
```

**2. Layer geometry computed before the view is in the hierarchy.** Oskar Groth traced upside-down text in ChatGPT
for Mac to adding subviews during draw/layout (`NSTextAttachmentCell.draw` calling `addSubview`, or
`updateNSView` adding views inside a `CATransaction` commit). The layer computed `geometryFlipped` without its
ancestors, which gave a text matrix with `d = -2`. Fix: build subviews in `makeNSView`, never in `updateNSView` or
`draw`. Defer hierarchy changes with `CATransaction.setCompletionBlock`, or use `NSTextAttachmentViewProvider`.
If our crash row uses an `NSViewRepresentable` (an `NSTextField` for selectable text, or an icon view) that adds
subviews in `updateNSView`, this is the prime suspect, especially if it is intermittent and fixes itself on scroll
or resize. **[blog: oskargroth.com]**

**3. A transform in SwiftUI.** `.scaleEffect(x: 1, y: -1)`, `.rotationEffect(.degrees(180))` or
`.rotation3DEffect` meant for a chevron, applied to an `HStack` instead of the `Image`. Also
`.flipsForRightToLeftLayoutDirection(true)` with an RTL environment (that mirrors horizontally, not vertically).
`grep -n "scaleEffect\|rotationEffect\|rotation3DEffect\|flipsFor" -r Sources/` settles it in seconds.
Slider + `rotationEffect` had its own rendering bug on 14.5. **[forum 756979]**

**4. The string itself.** Crash report names come from untrusted binaries:
- **Bidi controls** (U+202E RIGHT-TO-LEFT OVERRIDE, U+202D, U+2066–U+2069 isolates, U+200E/U+200F, U+061C)
  reverse character order (horizontal mirroring, e.g. `exe.gnp` tricks), not vertical flipping, but they also reorder
  surrounding row text. This is the "Trojan Source" class (CVE-2021-42574).
- **Upside-down look-alike letters** (ɐ q ɔ p ǝ ɟ ƃ ɥ ı ɾ ʞ ן ɯ u o d b ɹ s ʇ n ʌ ʍ x ʎ z, from "flip text" generators) are
  real code points and render "upside down" correctly. If the binary is literally named that way, it is not a bug.
- **Combining marks** (Zalgo), zero-width characters, and control characters (U+0000–U+001F, U+007F–U+009F).

Sanitize at the **Core** boundary (where the `.ips` JSON is parsed), and keep the raw value for "Show in Finder".

```swift
public enum DisplaySanitizer {
    public static func displayName(_ raw: String, maxLength: Int = 80) -> String {
        var out = String.UnicodeScalarView()
        var combiningRun = 0
        for s in raw.unicodeScalars {
            switch s.value {
            case 0x202A...0x202E, 0x2066...0x2069, 0x200E, 0x200F, 0x061C,    // bidi controls
                 0x200B...0x200D, 0x2060, 0xFEFF:                             // zero-width
                continue
            default: break
            }
            if s.properties.generalCategory == .control { continue }
            if s.properties.generalCategory == .nonspacingMark {             // cap Zalgo stacks
                combiningRun += 1
                if combiningRun > 2 { continue }
            } else { combiningRun = 0 }
            out.append(s)
        }
        let cleaned = String(out).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? "(unnamed process)" : cleaned
        return name.count > maxLength ? String(name.prefix(maxLength - 1)) + "…" : name
    }
}
```

(Test with swift-testing fixtures such as `"evil\u{202E}gnp.exe"`,
`"a\u{0301}\u{0301}\u{0301}\u{0301}"`, `"ʇsǝʇ"` (kept as is), `"\u{0000}x"`.) In SwiftUI also force LTR isolation for
the row: `Text(verbatim: name)` (no Markdown or localization lookup) `.environment(\.layoutDirection, .leftToRight)`
for path-like strings, `.lineLimit(1)` `.truncationMode(.middle)`.

**Diagnosis order:** (1) copy the name from the row: if the copied text reads correctly, it is a rendering bug (causes 1–3); if
not, it is the data (cause 4). (2) Dump `name.unicodeScalars.map { String($0.value, radix: 16) }` in a log line.
(3) Check whether the row is pure SwiftUI `Text`: pure SwiftUI `Text` does not flip on its own, so the bug is a
transform or a representable.

---

## Sources

- Apple forums, "NSApp.activate() does not work with menu bar (background) apps" (DTS replies, FB23508310, FB23519126): https://developer.apple.com/forums/thread/836619
- Apple doc, Passing control from one app to another with cooperative activation: https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation
- Apple doc, `NSApplication.activate()`: https://developer.apple.com/documentation/appkit/nsapplication/activate()
- Apple doc, `yieldActivation(to:)`: https://developer.apple.com/documentation/appkit/nsapplication/yieldactivation(to:)
- Apple forums, "Various menu bar NSStatusItem issues with macOS 27": https://origin-devforums.apple.com/forums/thread/836113
- Apple forums, "SwiftUI animation is laggy in NSStatusItem since macOS 26 Tahoe": https://developer.apple.com/forums/thread/803501
- Apple forums, "Any way to use a SymbolEffect in an NSButton": https://origin-devforums.apple.com/forums/thread/747451
- Apple forums, "Slider .rotationEffect broken in macOS 14.5": https://developer.apple.com/forums/thread/756979
- Peter Steinberger, Showing Settings from macOS Menu Bar Items: https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/ (and https://mjtsai.com/blog/2025/06/18/showing-settings-from-macos-menu-bar-items/)
- TablePro PR #2019 (openWindow ordering race, self-raising NSView): https://github.com/TableProApp/TablePro/pull/2019
- orchetect/MenuBarExtraAccess: https://swiftpackageindex.com/orchetect/MenuBarExtraAccess
- FluidMenuBarExtra: https://gitlink.org.cn/dnrops/fluid-menu-bar-extra
- Multi, Pushing the limits of NSStatusItem: https://multi.app/blog/pushing-the-limits-nsstatusitem
- fazm.ai, SwiftUI menu bar app with a floating window: https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices
- Paul Contreras, Wrapping it in a menu bar app: https://peerlist.io/paulcontre/articles/wrapping-it-in-a-menu-bar-app-and-three-things-that-broke
- Natalia Panferova (nilcoalescing), Customizing macOS window background in SwiftUI: https://nilcoalescing.com/blog/CustomizingMacOSWindowBackgroundInSwiftUI
- WWDC24 10148, Tailor macOS windows with SwiftUI (notes): https://wwdcnotes.com/documentation/wwdc24-10148-tailor-macos-windows-with-swiftui/
- Liquid Glass API reference (dpearson2699 swift-ios-skills): https://tessl.io/registry/dpearson2699/swift-ios-skills/3.6.0/files/skills/swiftui-liquid-glass/references/liquid-glass.md
- Oskar Groth, Debugging strange CALayers in ChatGPT (upside-down text): https://oskargroth.com/blog/debugging-strange-calayers-chatgpt
- Apple, Core Text common layout operations: https://developer.apple.com/library/mac/documentation/StringsTextFonts/Conceptual/CoreText_Programming/LayoutOperations/LayoutOperations.html

---

## Gotchas

1. `MenuBarExtra` has no `isPresented`; `isInserted` only hides the icon. Programmatic open needs AppKit or MenuBarExtraAccess.
2. The default `.menu` style turns SwiftUI into NSMenu items; use `.menuBarExtraStyle(.window)` for real layouts.
3. A borderless `NSPanel` returns `canBecomeKey == false`; override it or text fields never get keystrokes.
4. Set `.nonactivatingPanel` in the init style mask, not afterwards.
5. Position from `button.window?.screen`, never `NSScreen.main`, and clamp to `visibleFrame`.
6. A global mouse monitor never sees your own app's clicks; pair it with `didResignKey` for dismissal.
7. A status-item click can both close (global monitor) and reopen (action) the panel; ignore clicks inside the button's frame.
8. macOS 27 betas: `button.highlight(true)` no longer sticks and outside taps can be missed (FB23330269, FB23688090).
9. Do not set `statusItem.menu` if left click should open a panel; attach the menu temporarily on right click.
10. `NSStatusItem.view` is deprecated; host SwiftUI as a subview of `button` and drive `statusItem.length`.
11. SwiftUI animation inside a status-item `NSHostingView` is choppy on macOS 26; animate rendered images or CALayers.
12. `NSStatusBarButton` has no symbol effects; animate an `NSImageView` subview with `addSymbolEffect`.
13. Use monospaced digits in status item text, or the item jitters as the numbers change.
14. `NSApp.activate()` is only a request; an accessory app's new window can open behind the frontmost app (intended, per DTS).
15. `openWindow` only brings a window forward when it reuses an existing one; raise new windows from `viewDidMoveToWindow`.
16. Switch to `.regular` before opening a window; switching back to `.accessory` while it is visible sends it to the back.
17. Never call `setActivationPolicy` in `App.init()` (NSApp is nil); use `LSUIElement` for launch state.
18. `activate(ignoringOtherApps:)` is deprecated but still the only reliable fallback; isolate it in one helper.
19. Opening a URL from the frontmost app yields activation, but the yield is lost if the window opens late or is built fresh.
20. `openSettings` needs a live SwiftUI view and is a no-op on 26 from a bare MenuBarExtra; declare the hidden window before `Settings`.
21. Add `.defaultLaunchBehavior(.suppressed)` to Window scenes in menu bar apps, or a ghost window appears at launch or restore.
22. SwiftUI materials go flat when the app is inactive; use `NSVisualEffectView` with `state = .active` in panels.
23. Gate every Liquid Glass API with `if #available(macOS 26, *)`, including `ToolbarSpacer` inside the toolbar builder.
24. Do not put your own glass inside a system glass container (MenuBarExtra panel or toolbar on 26), or you get double glass.
25. Upside-down glyphs usually come from Core Text in a flipped context: reset `textMatrix` and flip the CTM.
26. Adding subviews in `updateNSView` or `draw` can compute layer flipping wrong and render text upside down.
27. RLO (U+202E) reverses text horizontally, it does not flip it vertically; strip bidi controls from untrusted process names.
28. "ʇsǝʇ"-style names are real code points; do not "fix" them, just display them verbatim.
29. Use `Text(verbatim:)` for process names so SwiftUI does no Markdown or localization lookup on untrusted strings.
