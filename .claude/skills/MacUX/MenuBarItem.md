# The status item: icon, click, and when to leave MenuBarExtra

The menu bar icon is the app's face; most users never see more. Panel content rules are in
`MenuPanel.md`; this file is the item itself and the container behind it.
Research and sources: `docs/research/2026-10-18-mac-gui-design/01-menubar-apps.md`, `03-…-mechanics.md`.

## Icon

- Menu bar is 24 pt (37 pt on notched Macs) but the usable item area is always **22 pt**. Glyph box
  **16–18 pt**, template image (`isTemplate = true`, the system reads alpha only), edges on the 2× pixel
  grid. No baked-in padding. Colour only when the colour is the meaning (recording red), and then it must
  read over any wallpaper: the Tahoe bar is transparent.
- State is a **shape or alpha** change, never colour alone. Disabled = 35 % alpha (Apple's value).
  Working = a short symbol effect (pulse, rotate) that stops when work stops; no motion while idle;
  Reduce Motion gets a static glyph (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`).
- Live text next to the icon: `monospacedDigitSystemFont`, one line at 12–14 pt or two stacked lines at
  9–10 pt. Reserve the widest string so `statusItem.length` changes only on a real state change, never per
  tick. Over ~80 pt wide → offer a separate status item per value instead (Dato).
- `statusItem.autosaveName` before the first sizing, so the slot survives relaunch and toggling.
- The user may hide the icon (System Settings › Menu Bar, the notch, Ice). Offer "Show in menu bar" in
  Settings, keep every job reachable from a window (Dock, Spotlight, URL scheme, hotkey), and on launch
  check `statusItem.button?.window?.occlusionState` to explain a hidden icon.

## What a click does

| Click | Does |
|---|---|
| Left | The menu or panel, on **mouse-down**, cached data first; a second click closes it |
| ⌥-left | The app's full window (Activity, main window), skipping the panel |
| Right / ⌃ | A small `NSMenu`: the full window, Settings… (⌘,), About, Quit |
| Global hotkey | Toggles the panel or the app's one quick action (configurable, off unless the app is keyboard-centric) |

HIG default is a menu. Use a panel only for live data, grids, text input or scrolling lists, and then make
it behave like a menu: closes on Esc, outside click, resign-key and a second icon click.

## MenuBarExtra or NSStatusItem + NSPanel

Stay on `MenuBarExtra(.window)` while the panel is static and opened only by clicking. Switch to AppKit
(`NSStatusItem` + a nonactivating `NSPanel` hosting the same SwiftUI root) as soon as you need any of:

- open or close from code (hotkey, URL, after an action): `MenuBarExtra` has no `isPresented`;
- a right-click menu separate from the left-click panel;
- a live label (text, badge, animated symbol);
- animated resize, pin/detach, or a text field that must reliably get keystrokes.

Recipe (full code in the mechanics report §1–2):

- Panel: `styleMask [.nonactivatingPanel, .borderless, .fullSizeContentView]` set in init; override
  `canBecomeKey` → `true` (else text fields never get keys) and `cancelOperation` → close;
  `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`;
  `NSHostingView.sizingOptions = [.preferredContentSize]`.
- Position from `button.window?.screen` (never `NSScreen.main`), clamped to `visibleFrame`, top edge pinned
  4 pt under the item. Recompute on every open.
- Dismiss: global mouse monitor **and** `didResignKeyNotification` (macOS 27 betas miss some outside clicks);
  ignore global clicks inside the button's own frame or the panel closes and reopens.
- Right-click: `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`; on right click attach the menu,
  `performClick`, detach. Never leave `statusItem.menu` set.
- Animated icon: `NSStatusBarButton` has no symbol effects; add an `NSImageView` subview and use
  `addSymbolEffect`. SwiftUI animation inside a status-item `NSHostingView` is choppy on macOS 26; render
  frames with `ImageRenderer` (template) or use Core Animation.
- Badge: a template image cannot carry a coloured dot; draw a separate non-template dot layer. The badge
  count and any in-window attention count come from **one** shared computed value.
- No dependency on MenuBarExtraAccess or FluidMenuBarExtra (AGENTS.md); they are reading material.

## Panel numbers (consensus of Stats, CodexBar, Itsycal, Control Center)

Width fixed 260–340 (default 320). Height follows content up to 70 % of the visible screen, then scrolls.
Outer padding 12 (dense) to 16. Rows ≥ 22, clickable rows 28. Inner corner radius = outer − padding
(concentric). At most 3 type sizes. Footer per AGENTS.md: Settings… (⌘,) and Quit (⌘Q).
In-panel keys: Esc close, ↩ default action, arrows move, ⌘R refresh, one letter for the primary verb.
