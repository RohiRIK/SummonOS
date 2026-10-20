---
type: Research
title: Premium native menu bar apps
description: "What makes a macOS menu bar app feel premium and native, from HIG, Bjango and four open-source apps."
tags: [research, design, menubar]
created: 2026-10-18
---

# What makes a macOS menu bar app feel premium and native (2024–2026)

Scope: macOS 15 Sequoia and macOS 26 Tahoe. The sources are Apple's HIG, Bjango's menu bar extra guidance, developer posts, product docs, and the source code of four open-source apps (Stats, Ice, Itsycal, CodexBar), which were cloned and read for real constants. The source of every claim is marked:
**[code]** = read in the repo, **[doc]** = vendor or Apple documentation, **[review]** = press or blog, **[obs]** = widely observed app behavior that no source fetched here confirms (verify it before relying on it).

---

## 1. Platform ground truth (what the system gives you)

- **Menu bar height is 24 pt** (Big Sur and later), per HIG and Bjango. On notched MacBook Pros the bar is **37 pt** at default scaling, and 27/29/33/34/37/43 pt at other scalings, but the **usable item area stays 22 pt**. A **16×16 pt circular glyph** matches the visual weight of system extras. Add no padding unless it is needed to center the glyph vertically. [doc] https://diagnostics.bjango.com/articles/designingmenubarextras/ · https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- **Template images:** the system reads only the alpha channel and tints it for light/dark/selected. Varying alpha is allowed for state (Wi-Fi bars, volume), and Apple uses **35 % opacity for disabled**. Provide a PDF/SVG or 1×+2× PNGs. Draw dynamic icons (clock, date) in code. [doc] Bjango.
- **HIG rules for extras:** *"Display a menu — not a popover — when people click your menu bar extra"* unless the functionality is too complex. *"Let people — not your app — decide whether to put your menu bar extra in the menu bar."* *"Avoid relying on the presence of menu bar extras"*: the system hides them when space runs out. Consider a Dock menu as a second entry point. [doc] HIG the-menu-bar.
- **HIG popovers (macOS):** make popovers detachable into a panel with *minimal appearance changes*. Auto-save on outside-click dismissal. Show one popover at a time. *Animate size changes so it doesn't look like a new popover replaced the old one.* Never use a popover for a warning. [doc] https://developer.apple.com/design/human-interface-guidelines/popovers.md
- **HIG menus (updated July 2025 and June 2026 for Tahoe's menu icons):** use menu-item icons *sparingly and with purpose*. Give a group **icons on all items or on none**. Keep submenus to one level and about 5 items. Use title-style capitalization and drop articles. Add "…" when more input is needed. Use changeable labels ("Show Map"/"Hide Map") or checkmarks for toggles. [doc] https://developer.apple.com/design/human-interface-guidelines/menus.md
- **Tahoe changes that affect us:** the menu bar is **transparent by default** (Liquid Glass). **Reduce Transparency** "restores the traditional menu bar". System Settings › **Menu Bar** now lets users turn off *any* app's extra. Control Center controls (WidgetKit `ControlWidget`) can sit standalone in the menu bar, though few third-party apps ship them yet. [review] https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3 · https://eclecticlight.co/2025/11/05/appearance-revisited-get-tahoe-26-1-looking-in-better-shape/ · https://www.macrumors.com/2025/08/01/macos-tahoe-review
  → Consequence: a status item can no longer assume a solid backing. Any color or non-template artwork must be legible over arbitrary wallpaper, and you must test with Reduce Transparency on.
- **The notch eats items.** Tailscale had enough "missing icon" reports to ship two fixes. The first uses `NSStatusItem` window `occlusionState` to detect a hidden icon and warn the user (it misfires on lid/display changes). The second is a full **windowed app reachable from Dock/Spotlight**, with a "mini player" mode. Their engineer on menu bar placement: *"You end up where you end up."* [doc] https://tailscale.com/blog/macos-notch-escape · https://tailscale.com/blog/windowed-macos-ui-beta

---

## 2. App-by-app teardown

### Stats (exelban/stats), open source, read in code
- **Status item = custom NSView inside `statusItem.button`**, with `button.image = NSImage()` (an empty image keeps the button's highlight and accessibility). Width is set explicitly: `statusItem(withLength: item.frame.width)`, and a `widthHandler` updates `length` only when it changes. [code] `Kit/module/widget.swift`
- **Width discipline:** the base widget width is **32 pt**, with spacing **2 pt** between widgets and a vertical margin of **2 pt**. Height is read from `NSApp.mainMenu.menuBarHeight`, falling back to 22. Combined mode sums the widget widths, adds `(n-1)*2`, and adds `2*2` edge padding. [code] `Kit/constants.swift`
- **Typography in the bar:** the "Mini" widget puts a **7 pt light** label above a **12 pt regular** value, or uses a **14 pt** value when there is no label. Stacked/speed widgets use **9 pt** two-line text. The values have **no monospaced digits** (system font, regular), which makes them jitter as they change. [code] `Kit/Widgets/Mini.swift`
- **Click:** `sendAction(on: [.leftMouseDown, .rightMouseDown])` (fires on *mouse-down*, which feels instant) posts a toggle for a **custom popup window**. It does not use an NSMenu or NSPopover. [code]
- **Popup anatomy:** a `NSWindow` with `[.titled, .fullSizeContentView]`, a transparent titlebar, `backgroundColor = .clear`, a shadow, and `collectionBehavior = .moveToActiveSpace`. **Width 264 pt, body 300 pt + header 42 pt, margins 8 pt, corner radius 6 pt, process rows 22 pt, separator rows 30 pt.** The header holds the module title at **16 pt regular** in the center, an Activity Monitor button on the left, and a ⌘-glyph "open module settings" button on the right. Both buttons are 24 pt wide and light-gray tinted. [code] `Kit/module/popup.swift`
- **Pin by dragging:** `windowWillMove` sets `locked = true` and shows a close button. `windowDidResignKey` hides the window only when it is not locked. Dragging the popup turns it into a persistent floating panel (the HIG "detachable popover" idea, done cheaply). [code]
- **Settings window 540×480 pt**, sidebar of modules. Status item positions persist via `autosaveName`, and Stats saves/restores `NSStatusItem Preferred Position` so a toggled-off item returns to the same slot. [code]
- Feels cheap: a gray-tinted header, non-monospaced live numbers, and a 6 pt radius that looks dated next to Tahoe's ~12–16 pt panels. Feels premium: mouse-down response, exact widths, and slot memory.

### CodexBar (steipete), open source, read in code
- **Icon:** drawn in code as an **18×18 pt template** (36×36 px at 2×) to "match the system menu bar size", with every rect **pixel-snapped** to the 2× grid. The two meter bars are **15 pt wide** ("uses the slot better without touching edges"). Optional "critter" faces blink. [code] `IconRenderer.swift`
- **Loading state lives in the icon:** six animation patterns (Knight Rider, Cylon, Pulse, Unbraid logo→bars morph…) are driven by a display link while fetching. The icon *becomes* the progress indicator, so there is no spinner in the panel. Overlays honor `accessibilityReduceMotion`. [code] `LoadingPattern.swift`, `StatusItemController+Animation.swift`
- **Click = real `NSMenu`** whose items host SwiftUI "cards" (`NSHostingView` in `NSMenuItem.view`). The **base card width is 310 pt**, grown to the widest measured section, with **20 pt horizontal padding** and section spacing of 6/10/6 pt. Fonts are system text styles only: `.headline` provider name, `.subheadline` account, `.footnote` meta, `.caption2.semibold` badges. Progress bars are **6 pt tall, fully rounded**. [code] `UsageMenuCardLayout.swift`, `StatusItemController+Menu.swift`, `UsageProgressBar.swift`
- **Hover/selection respects the menu highlight:** an environment flag `menuItemHighlighted` switches all text to `selectedMenuItemTextColor` and progress tracks to selection color at 22 % opacity, so custom cards invert exactly like native rows. [code] `MenuHighlightStyle.swift`
- **Live updates without rebuilding the open menu:** a refresh monitor updates the card subtitle in place ("Refreshing…") during AppKit menu tracking. ⌘R refreshes, and a global shortcut toggles the menu. [code/doc] `docs/ui.md`
- **Bar text is user-composed:** a token editor (icon, %, reset time, pace, cost) offers 1 or 2 lines, Small/Regular/Large type (**Large = 14 pt single-line, 10 pt stacked**), optional monospaced digits (default off), and Tight/Regular padding. Unknown values show "–" rather than a substitute. [doc] `docs/ui.md`
- **Settings:** a separate window with a sidebar, ⌘[ / ⌘] history, and About inside Settings. The app is LSUIElement and **temporarily becomes `.regular`** while Settings or update dialogs show. Stable `autosaveName` set before sizing, and invalid saved positions (beyond widest display + 512 pt) are cleared. [doc]
- Lesson: **an NSMenu with hosted SwiftUI cards** gets native open/close timing, keyboard navigation, highlight, and dismissal for free. You pay for that in highlight plumbing.

### Itsycal (sfsam), open source, read in code
- **Icon:** today's date drawn in code, **11.5 pt bold** (semibold for the outline variant), punched out of a **rounded rect (radius 4)** with XOR compositing, **16 pt tall, min width 17 pt (4 pt inner margins)**, template, and cached by name so it is redrawn only when the text changes. [code] `ViewController.m iconImageForText:`
- **Clock text uses monospaced digits only when seconds are shown**, *"so the status item doesn't move distractingly every second"*. It is built via a font-descriptor feature rather than `monospacedDigitSystemFont` because the latter draws lighter colons. [code]
- **Panel = custom borderless window with an arrow:** **arrow 8 pt, corner radius 16 pt, vertical padding 11 pt, ≥10 pt from screen edge.** A pin button keeps it open. [code] `ItsycalWindow.m`
- **Three size presets:** body font **11/13/15 pt**, calendar title **14/16/18 pt**, day cell **23/28/32 pt**, event dot **3/4/5 pt**. [code] `Sizer.m`
- **Single-key shortcuts inside the panel:** `w` toggles week numbers, `.` toggles locations, ⌘, opens Settings, ⇧⌘T opens Go to Date, ⌥⌘R refreshes, ⌘J joins the next meeting. A right-click/options menu holds About, Updates, Settings…, Quit. [code]

### Ice (jordanbaird), open source, read in code
- **Control item glyphs** are either a chevron drawn in code (**12 pt / 9 pt, 2 pt stroke**, template) or an SF Symbol (`isTemplate = true`). Custom images are scaled to fit **25×17 pt**. [code] `ControlItemImage.swift`
- **IceBar** (a floating bar for hidden items, the notch answer): `NSPanel` `[.nonactivatingPanel, .borderless, .fullSizeContentView]`, level `.mainMenu + 1`, `[.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]`, **no window animation**, continuous corner radius = **height/5**, and 10 pt horizontal padding. [code] `UI/IceBar/IceBar.swift`
- **Reveal triggers are user options:** click (on), hover (off), scroll (on), and **auto-rehide after 15 s** (on). ⌘-drag repositions dividers. [code] `GeneralSettingsManager.swift` · [review] https://www.macstories.net/roundups/managing-your-mac-menu-bar-a-roundup-of-my-favorite-bartender-alternatives/
- Vanilla is praised for *animating* items in and out. Bartender lost trust after a silent acquisition and permission reset. Trust is part of "premium". [review]

### iStat Menus 7 (Bjango)
- Nine independent items, each made of sub-elements (pie, graph, history graph, %, label). The 2024 v7 "full reboot" adds **stacked label+value modes**, separate **themes for the menu bar and for dropdowns**, a global **item spacing** control, and a "Show Background" option that drops the dark backing behind graphs on a light bar. ⌘-drag reorders. Combined mode lets several items share one slot, aimed at notched laptops. [doc] https://bjango.com/help/istatmenus7/welcome/ · [review] https://mjtsai.com/blog/2024/08/01/istat-menus-7 · https://macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/
- **Dropdown items are reorderable and toggleable by hovering the menu preview in Settings** (switches and drag handles appear on hover). The design is WYSIWYG configuration. [doc] https://bjango.com/help/istatmenus7/menus/

### Dato (Sindre Sorhus)
- **Bar text is a format string** (any datetime pattern) with four icon styles (date-in-calendar, bordered date, clock, none). Seconds are optional and labelled as costing CPU. **A separate optional status item shows the next event** (title length limit; filters: video calls only, has alert, accepted), and there are **separate items per time zone**. Many small items beat one wide item. [doc] https://sindresorhus.com/dato
- **Keyboard first:** a global toggle shortcut and in-panel keys. **`j` joins the next call**, ⌘+arrows "time travel" through zones (⌥ for finer steps), and `esc`/`space` exits. Double-click an event opens Calendar, and long-pressing a day opens it there. Context menu: Hide vs Mute. [doc]
- **Full-screen meeting alert:** `esc` dismisses and `return` joins. It skips all-day, muted, and recently-joined (15 min) events. Settings include "Vibrancy off" (solid background) and "Larger text". Shortcuts actions are available. [doc]

### Lungo (Sindre Sorhus) / Amphetamine
- Lungo's stance is **"focused and simple, with strong defaults"**: no custom durations ("decision fatigue"), Shortcuts for automation, and an opt-in **"Activate on Left-click"** setting so the default left click shows the duration menu. It refuses keep-awake with the lid closed in a bag for safety, and it animates the icon when active. [doc] https://sindresorhus.com/lungo
- Amphetamine is the maximalist opposite with triggers, schedules, and many states [obs]. It is premium for power users and cluttered for everyone else.

### Fantastical (mini window)
- **⌃⌥Space** toggles the mini window globally. **⌃⌘A** keeps it on top (pinning). **⌥-click the menu bar icon opens the full calendar window**, and **⌥-double-click** an event jumps to it there. In-panel keys: ⌘T today, ←/→ month, ⇧←/→ day, ⇧↑/↓ week, ⌘F search, ⌘↓ first result. [doc] https://flexibits.com/fantastical/help/shortcuts
- The pattern: **the modifier-click on the status item is the "open big window" gesture**, and keyboard navigation covers the whole panel.

### 1Password 8 (Quick Access)
- **The menu bar icon's click action is a setting**: open the app, show the menu, or open Quick Access. Quick Access is a **center-screen search window** (⌘⇧Space). It is context-aware: if an item matches the frontmost app it appears with no typing. Arrows move, → drills in, ↩ acts, Esc clears. ⌘C / ⇧⌘C / ⌥⌘C copy username/password/OTP, ⌘O opens in its own window, and ⇧⌘O opens in the main app. [doc] https://1password.com/blog/navigate-1password-quick-access

### Things 3 (Quick Entry)
- **⌃Space** opens a floating capture panel over the current app, and **⌃⌥Space** opens it with Autofill (links the current Safari/Mail/Finder item). Main-app shortcuts work inside it. **Esc discards, ⌘↩ saves**, and saving returns focus to the previous app. There is no success toast: the window closing is the confirmation. [doc] https://culturedcode.com/things/support/articles/2249437/

### Raycast
- Raycast's own UI is a center-screen launcher, and its menu bar icon is secondary [obs]. For extensions it documents menu bar rules: **avoid long titles**, group with sections (separators added automatically), use submenus sparingly, set `isLoading` during fetches, background refresh via `interval` (for example "5m"), **⌥ alternate items**, and per-item ⌘-shortcuts while the menu is open. [doc] https://developers.raycast.com/api-reference/menu-bar-commands
- Raycast Notes is a floating window with **fixed width and auto-resizing height (user-draggable)**, ⌘P switcher, and ⌘K actions. The ⌘K action palette is a reusable idea for any panel that has more actions than room. [review] https://www.macstories.net/reviews/raycast-overhauls-its-notes-feature/

### CleanShot X
- After a capture, a **Quick Access Overlay** thumbnail sits in a screen corner and acts on the file without opening a window: ⌘C copy, ⌘S save, ⌘W close, ⌘U upload, ⌘E annotate, and a right-click menu that includes Move to Trash. [review] https://www.imore.com/cleanshot-x-gains-new-keyboard-shortcuts-quick-access-overlay-more
- Its menu bar item opens a plain `NSMenu` of capture modes with visible shortcuts [obs]. The rich UI lives in transient overlays, not in the menu.

### Clop / Hand Mirror / Tailscale (smaller notes)
- **Clop:** the result appears as a **floating thumbnail you can drag** into other apps. Hotkey ⌃⇧C optimizes the clipboard, and number/minus keys downscale. The output is the UI. [doc] https://gittrend.io/repo/FuzzyIdeas/Clop
- **Hand Mirror:** click the icon to get an instant small camera preview, and click the notch for the same preview (paid). It is a single-purpose app that does one thing at once. [review] https://rss.boorghani.com/?p=142035
- **Tailscale:** the menu bar dropdown "can't use shape or color to convey state, lacks a search field, and hides features". Their fix is a windowed app (sidebar device list with search, detail pane, one-click copy IP / ping), a **red dot on the Dock icon** for critical errors, the error shown at the bottom of the sidebar, a debug window, and a **"mini player"** compact window. On quit, the user chooses whether to fully quit or stay in the menu bar. [doc] https://tailscale.com/blog/windowed-macos-ui-beta

### Award / "best designed" signal
- The 2025 and 2026 Apple Design Award Mac winners and finalists are games or iOS-first apps (Blue Prince, Cyberpunk 2077, Neva…). No menu bar utility made the list. [review] https://www.macstories.net/news/2025-apple-design-awards-winners-and-finalists-announced/ · https://9to5mac.com/2026/06/02/apple-reveals-apple-design-awards-app-and-game-winners-for-2026/
- **MacStories Selects 2025:** Best Mac App went to **Bloom** (its menu bar app holds favorites/locations, and it has shortcuts for nearly every action). The runner-up was **Supercharge** (a menu bar app with a shortcut per tool, Shortcuts actions, Finder services, and a shortcut-conflict debugger). Best Design was Sequel, praised for "Liquid Glass implementation that complements" its look. The common thread in praise: **keyboard coverage plus system integration (Shortcuts, Services)**. [review] https://www.macstories.net/stories/macstories-selects-2025-recognizing-the-best-apps-of-the-year/

---

## 3. Cross-cutting patterns

### 3.1 Status item icon
| Decision | Premium | Cheap |
|---|---|---|
| Artwork | Template, 16–18 pt glyph, drawn on the 2× pixel grid (CodexBar snaps every rect) | Full-color PNG logo, blurry at 1×, invisible on a transparent Tahoe bar |
| Live text | Monospaced digits for anything that ticks (Itsycal with seconds, CodexBar option) | Proportional digits jittering every refresh (Stats default) |
| Width | Fixed or rarely changing; Stats `length` updated only on change; Dato splits into separate items | Item that grows and shrinks every second, shoving neighbours around |
| Stacked text | 2 lines at 9–10 pt, label 7 pt (Stats, CodexBar "10 pt stacked") | 3+ lines or <7 pt text |
| State | Alpha/shape changes in the glyph, short animations while busy (CodexBar, Lungo) with Reduce Motion respected | Badges with color only; endless spinners |
| Position | `autosaveName` set before sizing, restore-on-toggle (Stats, CodexBar) | Item jumps to a new slot after every relaunch |

### 3.2 What click does
- **Plain `NSMenu`**: the HIG default. Used by CleanShot, Lungo, and Raycast extensions, and by CodexBar even for rich content (hosted SwiftUI cards). It opens instantly and dismisses naturally. One developer moved from NSPopover to NSMenu because the popover had "a slight delay and doesn't dismiss naturally". [review] https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6
- **Custom panel/window**: Stats (264 pt), Itsycal (arrow window), Fantastical, Dato. Use one when you need a grid, charts, text input, or scroll. It must replicate menu behavior: open on mouse-down, close on resign-key/outside click/Esc, and toggle on a second click.
- **Modifier/secondary clicks:** ⌥-click opens the big window (Fantastical), right-click gives the app menu (Itsycal), and the left-click action is configurable (1Password, Lungo).
- **Bigger window:** reached by ⌥-click, by dragging/pinning the panel (Stats drag-to-lock, Itsycal pin, Fantastical ⌃⌘A), by a header button (Stats ⌘-glyph), or through a Dock/Spotlight-launchable app (Tailscale).

### 3.3 Panel anatomy (consensus numbers)
- **Width:** 264 (Stats), 310 (CodexBar base), and roughly 7×cell + padding for Itsycal (23–32 pt cells → ~200–260 pt). Premium panels sit at **260–340 pt**, fixed width with content-driven height.
- **Padding:** 8 pt (Stats, dense) to 20 pt (CodexBar cards). Itsycal uses 11 pt vertical. For SwiftUI on Tahoe, 12–16 pt outer padding reads best next to system panels [obs, Control Center].
- **Corner radius:** 6 pt (Stats, dated) → 16 pt (Itsycal). Tahoe's own glass panels use larger, concentric radii, so the content radius should equal the outer radius minus the padding.
- **Header:** title at 13–16 pt plus 1–2 icon buttons at 24 pt (Stats). **Footer:** Settings… / Quit (our rule).
- **Type:** system text styles only (`.headline`, `.subheadline`, `.footnote`, `.caption2`). Body 11–13 pt, with a size preference for accessibility (Itsycal 11/13/15, Dato "Larger text").
- **Rows:** 22 pt (Stats process rows), with progress bars 6 pt tall and fully rounded (CodexBar).

### 3.4 Live data, loading, errors
- Show the last known value immediately (cache) and refresh in place. Never blank the panel while fetching (Raycast Cache API advice, CodexBar's in-place "Refreshing…").
- Show the loading state on the *icon* or as a subtitle, not as a modal spinner.
- Unknown values render as "–" (CodexBar) rather than 0 or a substitute.
- Critical errors escalate outside the panel: Tailscale's Dock red dot, occlusion warning, and error at the bottom of the sidebar. Never put a warning in a popover (HIG).

### 3.5 Keyboard
Every premium app has (a) a **global toggle shortcut** (Fantastical ⌃⌥Space, 1Password ⌘⇧Space, Things ⌃Space, Dato, CodexBar), (b) **⌘, for Settings and ⌘Q** inside the panel, (c) **⌘R refresh** (CodexBar; Itsycal ⌥⌘R), (d) **single-letter verbs** for the top action (Dato/Itsycal `j`/⌘J join, Itsycal `w`), and (e) **Esc to dismiss, ↩ for the default action** (Things, Dato). An **⌥ alternate** reveals power actions (Raycast).

### 3.6 Settings and onboarding
- Settings live in a separate window. On macOS 14–26 that needs an **activation-policy dance**: `.accessory` → `.regular`, activate, `openSettings()`, then `orderFrontRegardless`, and back to `.accessory` when Settings closes. A hidden `Window` scene must be declared **before** `Settings`, or `openSettings` fails silently. `SettingsLink` inside `MenuBarExtra` is unreliable. [review] https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/
- Onboarding: offer "show in menu bar" during setup (HIG). Show a product tour only on install or major update (Tailscale). Check whether the icon is hidden (occlusion) and say so.
- Strong defaults beat options (Lungo FAQ). Put configuration where it can be previewed (iStat Menus' hover-to-edit preview, CodexBar's token editor with live preview).

---

## 4. Rules we should adopt

1. **Icon size:** the status item glyph is a template image with an **16–18 pt** content box inside the **22 pt** usable height. It has no baked-in vertical padding and every edge sits on a whole 0.5 pt (2× pixel) boundary. Test: render at 1× and 2× with no anti-aliased half-pixel edges on straight lines.
2. **Template only:** `isTemplate == true` for every bar image unless the color carries meaning. A color icon must pass contrast on both a white and a black wallpaper with the Tahoe transparent bar, and with Reduce Transparency on.
3. **State via alpha/shape, not color alone:** disabled = **35 % alpha**. Any state shown by color in the bar has a shape or glyph change too.
4. **Bar text:** live numbers use **monospaced digits**. Single-line text is **12–14 pt**. Stacked text is **2 lines max at 9–10 pt**, with labels no smaller than **7 pt**.
5. **Width stability:** the status item `length` changes at most once per user-visible state change and never on a per-second tick. Reserve the widest expected string (for example "100%") with a fixed width. Test: a value cycling 0–100 never moves neighbouring items.
6. **Slot memory:** set `autosaveName` before the first sizing. Toggling the item off and on restores its previous position.
7. **Click latency:** the panel or menu appears on **mouse-down**, within one frame (<16 ms of work on the main thread before ordering front), and shows cached data first. A second click on the item closes it.
8. **Choose the container deliberately:** use an `NSMenu` (optionally with hosted SwiftUI rows) when content is a list of actions or ≤ ~12 rows. Use a custom panel only for grids, charts, text input, or scrolling content. Never use NSPopover for an always-used panel.
9. **Panel width** is fixed at **260–340 pt** (default **320 pt**). Height follows content up to **≤ 70 % of the visible screen height**, then the panel scrolls internally. Animate size changes (HIG).
10. **Panel spacing:** outer padding **12 pt** (dense data) or **16 pt** (default). Rows are **≥ 22 pt** tall with **28 pt** for clickable rows. Corner radius matches the container: inner radius = outer radius − padding.
11. **Typography:** use system text styles only, with no hard-coded font names. Use **≤ 3 sizes per panel** (for example headline 13 pt semibold, body 13 pt, footnote 11 pt) and secondary text via `.secondary`, not custom grays.
12. **Highlight parity:** custom rows in an NSMenu switch all text and tints to `selectedMenuItemTextColor` when highlighted (CodexBar pattern). Custom panels show hover on clickable rows with a **4–6 pt** radius background at system fill.
13. **Dismissal:** the panel closes on Esc, outside click, resign-key, and a second icon click. Work in progress is auto-saved, never discarded, on outside-click dismissal (HIG).
14. **Pin/detach:** any panel the user might watch while working can be pinned (a pin button or dragging the panel) and stays open until explicitly closed. The detached form looks identical to the attached one.
15. **Big window access:** **⌥-click** on the status item opens the full window or the most relevant view, and the panel also exposes it in its header or footer. Right-click shows a compact `NSMenu` with Settings…, About, and Quit.
16. **Keyboard coverage:** a configurable global toggle shortcut (off by default unless the app is keyboard-centric). In the panel: **⌘,** Settings, **⌘Q** Quit, **⌘R** refresh, **Esc** close, **↩** default action, arrow keys move selection, and one single-letter key for the primary verb. Every shortcut is visible in a menu or tooltip.
17. **Loading:** never blank the panel to fetch. Show the last value with a relative "Updated 2 min ago" or an inline "Refreshing…", and show loading in the bar icon as a short animation that respects **Reduce Motion** (static fallback).
18. **Unknown and error values:** unknown renders as "–", never "0" or a stale value presented as fresh. Errors appear inline in the panel with one recovery action ("Retry", "Open Settings…"). Never use a popover or alert for routine failures, and use an alert only for destructive or blocking issues.
19. **Empty states** carry one sentence explaining why and one button that fixes it (grant permission, add account). They are never a blank panel.
20. **Settings window:** a separate SwiftUI `Settings` scene, `.formStyle(.grouped)`, opened via the activation-policy switch (`.regular` → activate → open → back to `.accessory` on close). The hidden helper `Window` scene is declared before `Settings`.
21. **Visibility is the user's choice:** offer "Show in menu bar" in onboarding and in Settings. Detect occlusion (`statusItem.button.window.occlusionState`) on launch and explain how to reveal a hidden icon. A Dock menu or Spotlight-launchable window remains a reachable fallback.
22. **Split rather than widen:** when the bar needs to show more than one independent value, offer **separate status items** (Dato pattern) or one combined item, each ≤ **~80 pt** wide. Never use a single item wider than **120 pt** by default.
23. **Menus:** title-style capitalization, no articles, "…" on items that open more UI. A group has icons on **all items or none**, submenus stay **one level deep with ≤ 5 items**, and power variants appear as **⌥ alternates**.
24. **Strong defaults:** the first launch works with zero configuration, and every option added must name the user problem it solves (Lungo rule). Where configuration is visual, show a live preview.
25. **Appearance QA matrix:** before shipping, check the bar and panel in Light and Dark, Tahoe Clear and Tinted glass, Reduce Transparency, Increase Contrast, over a white and a busy wallpaper, on a 24 pt bar and a 37 pt notched bar, and at a larger text size if one is offered.

---

## Sources
- Apple HIG, The menu bar: https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- Apple HIG, Menus: https://developer.apple.com/design/human-interface-guidelines/menus.md
- Apple HIG, Popovers: https://developer.apple.com/design/human-interface-guidelines/popovers.md
- Bjango, Designing macOS menu bar extras: https://diagnostics.bjango.com/articles/designingmenubarextras/
- Bjango, iStat Menus 7 help: https://bjango.com/help/istatmenus7/welcome/ · https://bjango.com/help/istatmenus7/menus/
- Michael Tsai on iStat Menus 7: https://mjtsai.com/blog/2024/08/01/istat-menus-7 · MacRumors: https://macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/
- Stats source: https://github.com/exelban/stats (`Kit/constants.swift`, `Kit/module/widget.swift`, `Kit/module/popup.swift`, `Kit/Widgets/Mini.swift`)
- CodexBar source and docs: https://github.com/steipete/CodexBar (`IconRenderer.swift`, `UsageMenuCardLayout.swift`, `MenuHighlightStyle.swift`, `docs/ui.md`)
- Itsycal source: https://github.com/sfsam/Itsycal (`ItsycalWindow.m`, `ViewController.m`, `Sizer.m`)
- Ice source: https://github.com/jordanbaird/Ice (`ControlItemImage.swift`, `UI/IceBar/IceBar.swift`)
- Peter Steinberger, Showing Settings from macOS menu bar items: https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/
- Multi, Pushing the limits of NSStatusItem: https://multi.app/blog/pushing-the-limits-nsstatusitem
- Building a native menu bar app (NSMenu vs NSPopover): https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6
- Tailscale: https://tailscale.com/blog/macos-notch-escape · https://tailscale.com/blog/windowed-macos-ui-beta
- Dato: https://sindresorhus.com/dato · Lungo: https://sindresorhus.com/lungo
- Fantastical shortcuts: https://flexibits.com/fantastical/help/shortcuts
- 1Password Quick Access: https://1password.com/blog/navigate-1password-quick-access
- Things Quick Entry: https://culturedcode.com/things/support/articles/2249437/
- Raycast menu bar commands: https://developers.raycast.com/api-reference/menu-bar-commands · Raycast Notes: https://www.macstories.net/reviews/raycast-overhauls-its-notes-feature/
- CleanShot X overlay shortcuts: https://www.imore.com/cleanshot-x-gains-new-keyboard-shortcuts-quick-access-overlay-more
- Clop: https://gittrend.io/repo/FuzzyIdeas/Clop · Hand Mirror: https://rss.boorghani.com/?p=142035
- Menu bar managers roundup: https://www.macstories.net/roundups/managing-your-mac-menu-bar-a-roundup-of-my-favorite-bartender-alternatives/
- macOS Tahoe: https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3 · https://www.macrumors.com/2025/08/01/macos-tahoe-review · https://eclecticlight.co/2025/11/05/appearance-revisited-get-tahoe-26-1-looking-in-better-shape/
- Awards: https://www.macstories.net/stories/macstories-selects-2025-recognizing-the-best-apps-of-the-year/ · https://www.macstories.net/news/2025-apple-design-awards-winners-and-finalists-announced/ · https://9to5mac.com/2026/06/02/apple-reveals-apple-design-awards-app-and-game-winners-for-2026/
