# Apple's macOS design language, 2025–2026: Tahoe (26), Liquid Glass, and macOS 27 "Golden Gate"

Research date: 2026-10-18. Sources: the HIG pages' Markdown (`developer.apple.com/design/human-interface-guidelines/<page>.md`), WWDC25 and WWDC26 session transcripts, Apple developer documentation JSON (for API availability), and press coverage of WWDC26.

Confidence labels used below:
- **[HIG]**: the current Human Interface Guidelines text says this.
- **[WWDC25]** or **[WWDC26]**: an Apple engineer or designer said this in a session.
- **[Docs]**: Apple's API reference, with the platform availability checked.
- **[Press]**: third-party reporting. Treat it as likely, not authoritative.
- **[Ours]**: our own convention or a measurement. Apple publishes no number for these.

---

## 0. Timeline: what changed when

| When | What |
|---|---|
| WWDC25 (June 2025) | macOS 26 Tahoe ships Liquid Glass. Floating, inset glass sidebar. Glass toolbar groups. Scroll edge effects. Larger, concentric window corners. Taller controls and a new `extraLarge` size. Icons in every menu. Layered app icons from Icon Composer. SF Symbols 7, which adds Draw On/Off and gradients. |
| Sept / Dec 2025 HIG updates | Materials (Sept 9), and toolbars, buttons and color (Dec 16) are revised for Liquid Glass. Typography gains "emphasized weight" columns. |
| WWDC26 (June 8, 2026) | macOS 27 "Golden Gate" (Apple now writes the version before the name). This release is a correction of Tahoe; see the next list. |
| Sept 9, 2026 | Layout page updated "to reflect current best practices." |

What macOS 27 changed:
- **Sidebars:** they extend to the window edge again, with no floating "blob" margins, and content still refracts beneath them. Sidebar selection uses semibold text. Sidebar icons keep their color.
- **Toolbars:** the toolbar is unified with clearer dividers. Bordered toolbar items over the sidebar now get glass too.
- **Scroll edges:** the automatic scroll edge style resolves to **hard** when free-floating text, such as the window title, sits over the content. System Settings drops the progressive blur.
- **Menus:** icons in menus are now minimal by default (`NSMenuItem.preferredImageVisibility`, SwiftUI `.labelStyle(.titleAndIcon)` to opt in).
- **Glass:** a user transparency slider, from opaque to clear. A new "interactive" bounce for glass controls on the Mac. "Show Borders" is decoupled from Increase Contrast. A new AppKit concentricity API: `cornerConfiguration` with `.containerConcentric`.
- **New beta tools:** Icon Composer 2 and SF Symbols 8.

Sources: [WWDC26 289 Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/), [WWDC26 269 What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/), [mjtsai.com 2026-06-09 roundup](https://mjtsai.com/blog/2026/06/09/), [HIG sidebars change log](https://developer.apple.com/design/human-interface-guidelines/sidebars) ("June 8, 2026: Updated guidance for sidebar icon colors").

**Implication for us:** our minimum target is macOS 15, with glass gated by `#available(macOS 26, *)`. Design so the result looks right under both 26 (floating sidebar, soft edges) and 27 (edge-to-edge sidebar, hard edges under titles). The way to do that is to use system containers (NavigationSplitView, toolbar, List, Form) and never hand-draw these surfaces.

---

## 1. The core model: two layers

**[HIG Materials]** "Liquid Glass forms a distinct functional layer for controls and navigation elements — like tab bars and sidebars — that floats above the content layer."

- **Don't use Liquid Glass in the content layer.** The HIG's one exception is transient interactive controls inside content, such as sliders and toggles, which lift into glass while you drag them. Use *standard materials* for content-layer surfaces like app backgrounds. In SwiftUI that is `Material` (`.regularMaterial`, `.thinMaterial`, and so on); in AppKit, `NSVisualEffectView.Material`.
- **Use glass sparingly.** Standard components adopt it automatically. In custom UI, "limit these effects to the most important functional elements."
- **Never put glass on glass.** [WWDC25 219]: "When placing elements on top of Liquid Glass, avoid applying the material to both layers. Instead, use fills, transparency, and vibrancy for the top elements."
- **Two variants, never mixed** ([WWDC25 219]):
  - **Regular** (`Glass.regular`, the default) is adaptive and works over any content at any size. Use it for anything with much text: alerts, sidebars, popovers.
  - **Clear** (`Glass.clear`) is permanently more transparent and has no adaptive behavior. Use it only when all three hold: the element sits over media-rich content, a dimming layer won't harm that content, and the content on top is bold and bright. **[HIG]** Add a **35% dark dimming layer** if the underlying content is bright.
  - `Glass.identity` means no effect, which is useful for conditional glass.
- **Adaptive behavior.** Small glass, such as toolbars and tab bars, flips between light and dark with the content beneath it. Large glass, such as sidebars and menus, does **not** flip ("their surface area is too big") and is more opaque. Symbols on glass flip with it, so leave them monochrome [WWDC25 219; HIG Color].
- **Window state.** When a window loses focus, glass "visually recedes" [WWDC25 219]. In SwiftUI, use `@Environment(\.appearsActive)` to dim custom chrome in an inactive window [WWDC26 269; Docs: macOS 10.15+].
- **Accessibility comes free.** Reduce Transparency makes glass frostier. Increase Contrast makes elements mostly black or white with a contrasting border. Reduce Motion removes the elastic effects. You get all of this only if you use the real material, not a fake one [WWDC25 219].
- **Steady-state rule.** At launch, the top of a scroll view, or any resting state, avoid content intersecting glass. "Reposition or scale the content to maintain separation" [WWDC25 219; HIG Color].

---

## 2. Window anatomy on modern macOS

A Tahoe or Golden Gate primary window, from top to bottom and from leading to trailing:

1. **Frame and unified toolbar.** The traffic lights sit at the leading edge, then the sidebar toggle. The title (under 15 characters, never the app name) and an optional document menu sit on the leading side. Common actions go in the center area, which is customizable and collapses into the system overflow menu. Inspector toggles, search, the More menu and the single primary action go at the trailing edge, which is always visible [HIG Toolbars].
2. **Sidebar** (leading). This is glass. In 26 it floats as an inset pane, concentric with the window corner. In 27 it is edge-to-edge again, and content still flows beneath it. Its glass is more opaque than toolbar glass [HIG Color; WWDC25 310; WWDC26 289].
3. **Content and detail column(s).** These extend edge to edge under the toolbar and sidebar. A scroll edge effect separates the content from the floating chrome.
4. **Inspector** (trailing). This is "edge-to-edge glass that sits alongside the content", not floating [WWDC25 310]. SwiftUI: `.inspector(isPresented:)` plus `.inspectorColumnWidth(min:ideal:max:)` [Docs, macOS 14+].
5. **Optional bottom bar / status bar.** It is rare. Use it only for non-critical, window-related information, as with Finder's item count and free space. Never put critical controls there, because windows get dragged partly off the bottom of the screen [HIG Windows, Layout].

**Corner radii and concentricity** [WWDC25 310, 356]:
- Windows **with toolbars** use a larger radius "designed to wrap concentrically around the glass toolbar elements, scaling to match the size of the toolbar." **Titlebar-only** windows keep a smaller radius around the traffic lights. Apple publishes no numbers. Community measurements put toolbar windows at about 26 pt and titlebar-only windows at about 16 pt. [Ours] Never hard-code these; derive radii from the container.
- Apple uses three shape types:
  - **fixed:** a constant radius.
  - **capsule:** the radius is half the height.
  - **concentric:** the radius equals the parent radius minus the padding.
- Fix corners that look "pinched or flared" by making the inner shape concentric. For components used both nested and standalone, use **concentric with a fallback radius**.
- SwiftUI: `ConcentricRectangle`, `.rect(corners: .concentric(minimum:))`, and `.containerShape(_:)` to declare the container [Docs, macOS 26].
- AppKit 26: `NSView.LayoutRegion` with corner adaptation, so content avoids the rounded corner. AppKit 27: override `cornerConfiguration` and return `NSViewCornerConfiguration` with `.containerConcentric` plus a minimum radius [WWDC26 289].
- In 26, content near a window corner can be clipped by the larger radius. Use safe-area or layout-region insets rather than fixed padding.

**Split views** [HIG Split views]:
- Prefer the **thin 1-pt divider**.
- Set min and max pane sizes so the divider never disappears.
- Persistently highlight the selection in every pane that leads to the detail view.
- Give people several ways to restore a hidden pane: a toolbar button, a View-menu command and a shortcut.

**Sidebars** [HIG Sidebars]:
- Show no more than **two levels** of hierarchy. If you need more, add a content column.
- Use succinct group labels and SF Symbols for items.
- Make it hideable: a toolbar button plus View ▸ Show/Hide Sidebar (⌃⌘S).
- Consider auto-collapsing it when the window gets narrow, as Mail does.
- Don't put critical items at the bottom.
- Row height, text and glyph size follow the user's *Sidebar icon size* setting (small, medium or large). Don't hard-code them.
- **Icon color:** icons default to the accent color and follow the user's accent choice. Use fixed colors sparingly and only when the color means something, like Mail's yellow VIP star (2026 update). A fixed-color sidebar icon is not overridden by the accent setting [HIG Color].
- Remove any legacy `NSVisualEffectView` sidebar material. It blocks the glass [WWDC25 310].

**Extending content under the sidebar:**
- **[HIG]** Extend visually rich content beneath the sidebar, either with horizontal scrolling or with `backgroundExtensionEffect()`. That modifier mirrors and blurs the view into the safe-area region, so artwork looks edge-to-edge without being covered [Docs, macOS 26].
- AppKit equivalents: `NSBackgroundExtensionView`, and `automaticallyAdjustsSafeAreaInsets = true` on the content split item (not on the sidebar item).
- Keep text and controls *above* the extension effect to avoid distortion. Scroll views extend under the sidebar by default [WWDC25 356].

---

## 3. Toolbars

**[HIG Toolbars, Dec 2025]** and [WWDC25 310, 323, 356]:

- **Glass is automatic.** Every toolbar item sits on glass, and the toolbar floats over content. AppKit groups plain buttons onto one piece of glass and splits other control types into their own pieces: segmented controls, pop-ups, search.
- **Grouping:**
  - Group by function and frequency, with a maximum of **three groups**.
  - Use `ToolbarItemGroup` to share one glass background.
  - `ToolbarSpacer(.fixed)` splits groups; `ToolbarSpacer(.flexible)` pushes groups apart. Mail, for example, has a leading filter and a trailing search plus compose.
  - `.sharedBackgroundVisibility(.hidden)` takes an item off the glass [Docs, macOS 26].
  - AppKit: `NSToolbarItemGroup`, spacers, and `isBordered = false`.
- **Non-interactive items** such as titles and status text should **not** sit on glass, or they read as buttons. Use `.sharedBackgroundVisibility(.hidden)` or `isBordered = false` [WWDC25 310].
- **Never group a symbol with a text button.** They read as a single button. Text-labeled buttons get their own containers, separated by fixed space [HIG; WWDC25 356].
- **Symbols, not borders.**
  - Use system SF Symbols in the outline variant, with no circled or bordered symbols. The group is the container, and hover and pressed states are drawn by the system.
  - Use text only where no symbol is clear, such as "Edit" or "Select."
  - Icons render **monochrome** in toolbars by default.
- **Tinting:**
  - Tint only to convey meaning, like a call to action, never for decoration.
  - Mark exactly **one** primary action, on the trailing side, prominent and tinted with the accent color: `.buttonStyle(.glassProminent)` or a `ToolbarItem(placement: .confirmationAction)`. AppKit uses `NSToolbarItem.style = .prominent` and `backgroundTintColor`.
  - On macOS the primary action reads as "a prominent text button" [WWDC25 356].
- **No custom bar backgrounds.** "Reduce the use of toolbar backgrounds and tinted controls." Remove any darkening or background views behind bar items; they interfere with the scroll edge effect [HIG; WWDC25 323].
- **Badges:** `.badge(_:)` on toolbar item content; AppKit uses `NSItemBadge`.
- **Overflow:**
  - macOS adds the overflow menu automatically. Don't build one, and avoid layouts that overflow at the default size.
  - **Every toolbar command must also exist in the menu bar,** because users can hide or customize the toolbar [HIG macOS].
  - Let users customize the toolbar in long-use apps: `.toolbar(id:)` with `ToolbarItem(id:)`.
- **WWDC26 toolbar APIs:**
  - `visibilityPriority(_:)` and `topBarPinnedTrailing` are presented for resizable windows.
  - `ToolbarOverflowMenu` is **iOS, iPadOS, Catalyst and visionOS 27 only**. It is not available on native macOS [Docs].
  - `toolbarMinimizeBehavior` is iOS-oriented.

---

## 4. Scroll edge effects

[WWDC25 219, 356, 310; HIG Layout; WWDC26 289]

- **What they are:** "not decorative," they "don't block or darken like overlays." Use them only where floating UI overlaps scrolling content. They replace hard dividers.
- **Soft** (the default) progressively fades and blurs content. It suits glass buttons.
- **Hard** is "mostly used on macOS": a more opaque, uniform backing. Use it for interactive text, controls without backgrounds, and pinned table or column headers.
- **macOS 27:** the automatic style resolves to hard when free-floating text, such as a window title, is present.
- **One effect per view.** Never stack or mix soft and hard. In a split view, each pane may have its own effect, but keep their heights consistent.
- **SwiftUI:**
  - `.scrollEdgeEffectStyle(.hard | .soft | .automatic, for: .top)`
  - `.scrollEdgeEffectHidden(_:for:)`
  - `.safeAreaBar(edge:alignment:spacing:content:)` adds a custom bar, such as a filter row, that *participates* in the edge effect and insets the safe area [Docs, macOS 26].
- **AppKit:** `NSScrollEdgeEffectStyle`, titlebar accessories, and the new **split item accessories** (`NSSplitViewItemAccessoryViewController`, top- or bottom-aligned per pane).
- **[HIG Layout]** "Instead of applying a solid or semi-opaque background color beneath controls, use a scroll edge effect."

---

## 5. Custom glass (SwiftUI and AppKit)

- `.glassEffect(_ glass: Glass = .regular, in shape: some Shape = .capsule)`. Text inside automatically gets a vibrant, adaptive color [WWDC25 323].
- `.glassEffect(.regular.tint(.accentColor))` is for meaningful emphasis only. `.interactive()` scales, bounces and shimmers on interaction. Since macOS 27 it is tuned for the pointer: "use it with controls and buttons … a little goes a long way" [WWDC26 289, 269].
- **`GlassEffectContainer(spacing:)`** is mandatory when several glass shapes are near each other. Glass can't sample glass, and one container gives one shared sampling pass, so the result is correct and faster. Shapes within the spacing distance blend together. Use `glassEffectID(_:in:)` with a `@Namespace` for morphing, `glassEffectUnion(id:namespace:)` to merge shapes, and `glassEffectTransition(_:)` for transitions.
- Apply glass to the control itself, not to its inner subviews [WWDC25 356].
- AppKit equivalents:
  - `NSGlassEffectView` takes a `contentView`. Don't put it behind content as a sibling. It has `cornerRadius` and `tintColor`.
  - `NSGlassEffectContainerView` has `spacing`.
- **Button styles:**
  - `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)`.
  - AppKit: the `.glass` bezel style plus `bezelColor`, and `tintProminence` (`.automatic`, `.none`, `.secondary`, `.primary`).
  - Destructive buttons use secondary-prominence red so they don't outshout the default button.

---

## 6. Controls

[WWDC25 310, 323, 356; HIG Buttons, Accessibility]

- **Sizes:** mini, small, regular (medium), large, and **extraLarge** (`.controlSize(.extraLarge)`). In 26, mini, small and medium are **slightly taller** than in Sequoia. Never hard-code control heights. For dense inspectors and popovers, use a smaller `.controlSize`; AppKit uses `prefersCompactControlSizeMetrics`.
- **Shapes:** mini through medium stay **rounded rectangles** to preserve horizontal density. Large and extra-large become **capsules**. Override with `.buttonBorderShape(.capsule | .roundedRectangle(radius:) | .circle)`; AppKit uses `borderShape`. Capsules on the desktop are for standout actions.
- **Extra-large** is reserved for the action people launch the app to do, such as Play or Call.
- **Hierarchy:**
  - Use at most one or two prominent buttons per view.
  - Distinguish the preferred choice by **style, not size**.
  - The default button responds to Return (`.keyboardShortcut(.defaultAction)`).
  - Never give a destructive action the primary role.
- **Labels:** append an ellipsis "…" when a button opens another window or view. Use title-style capitalization and start with a verb.
- **Sliders:** tick marks appear automatically with `step:`. `neutralValue` anchors the fill, as in a 1× playback speed. AppKit: `tintProminence = .none` gives a slider no fill.
- **Hit targets** [HIG Accessibility]: on macOS, **default 28×28 pt, minimum 20×20 pt**. Image buttons need about 10 px of padding around the image.
- Square, help and image buttons belong **in views, not in the window frame**. In the toolbar, use toolbar items.

---

## 7. Menus, the menu bar and menu bar extras

**The menu bar** [HIG The menu bar]:
- It is **24 pt tall**, and is transparent by default in Tahoe.
- When space runs out, the system hides menu bar extras.
- System Settings ▸ Menu Bar lets users turn any extra off [Press: MacStories].

**Menu bar extras:**
- Use an SF Symbol or a template image. Shapes are drawn in black and clear; the system recolors them for light and dark bars and the selected state.
- **"Display a menu — not a popover — when people click your menu bar extra,** unless the functionality is too complex for a menu." In SwiftUI that means `MenuBarExtra { … }` with `.menuBarExtraStyle(.menu)` by default and `.window` only when justified.
- Let people decide whether the extra appears; offer the option in Settings and during setup. Don't rely on it being visible or on its position. Expose the same functions elsewhere too, for example in a Dock menu.

**Keyboard access** [WWDC26 289]:
- Status items take part in keyboard navigation across the menu bar.
- In AppKit, a status item that shows a custom window must use the **expanded interface session** delegate (`statusItem(_:didBeginExpandedInterfaceSession:)` and its end counterpart, plus `cancel()`) so focus behaves correctly.
- SwiftUI `MenuBarExtra` handles this for you.

**Menu icons:**
- In **26**, every menu gets leading icons, in a single scannable column per section.
- In **27** the default reversed to **minimal icons**: "reserve them for key actions." The HIG (June 2026) says:
  - Use menu item icons sparingly and with purpose.
  - Give icons to all items in a group or none.
  - Use standard icons for common actions such as Copy, Share and Delete.
  - "Don't display an icon if you can't find one that clearly represents the menu item."
  - For related actions, use the symbol once to introduce the group and let the text do the rest.
- To opt an item in: SwiftUI `.labelStyle(.titleAndIcon)`; AppKit `NSMenuItem.preferredImageVisibility = .visible` (macOS 27).

---

## 8. Search

[HIG Search fields; WWDC25 323; WWDC26 292]

- **Placement on Mac** (keep it the same as on iPad):
  - In a **split-view app**, put search at the **trailing edge of the toolbar**, as Mail, Notes and Voice Memos do. In SwiftUI, put `.searchable` on the `NavigationSplitView` so it applies to the whole window.
  - Put it **at the top of the sidebar** when it filters the sidebar, as System Settings and Stocks do: `.searchable(placement: .sidebar)`.
  - Make it **a dedicated sidebar item or tab** for discovery-heavy apps, such as Music and TV: `Tab(role: .search)`.
- The field sits on its own glass and may collapse into a button when space is short. Recent searches can appear in a menu.
- **Behavior:**
  - Use placeholder text that states the scope.
  - Search as the user types.
  - Default to the broad scope and narrow it with a scope bar or tokens (`searchScopes`, `searchable(text:tokens:)`).
  - Auto-focus the field when the user navigates to a dedicated search area.

---

## 9. Lists, tables and selection

[HIG Lists and tables; WWDC26 289]

- Prefer text rows. Keep row text succinct. Use middle truncation when both the start and end of a string matter, as with file names: `.truncationMode(.middle)`.
- On macOS:
  - Sort by clicking column headers, and reverse the order on a second click (`Table` with `sortOrder`).
  - Let people resize columns.
  - Consider alternating row colors in wide multi-column tables (`.alternatingRowBackgrounds()`).
  - Use an outline view for hierarchy (`OutlineGroup`, `List(children:)`).
  - Column headings are nouns in title case with no punctuation.
- Selection uses system colors: `selectedContentBackgroundColor` for a key window, and `unemphasizedSelectedContentBackgroundColor` when the window is not key. A custom selection must change appearance in a non-key window.
- In macOS 27, sidebar selection becomes semibold. Don't fake selection weight yourself; let `List(selection:)` handle it.
- Use the HIG `.inset` or `.sidebar` list style rather than hand-built row backgrounds. Lists of over 100k items load about 6× faster in SwiftUI 26 [WWDC25 256].

---

## 10. Color

[HIG Color]

- **Glass has no color of its own.** It takes color from the content behind it.
- Apply color **sparingly**, to status indicators and primary actions. To emphasize a primary action, color the *background* (the prominent style), not the symbol.
- If the content layer is colorful, keep toolbar and button labels monochrome. Never use the same color for control labels and the content beneath them.
- Put brand color in the content layer, not on the glass [WWDC25 219].
- **Semantic colors on macOS** (use these, never hex):
  - Text: `labelColor`, `secondaryLabelColor`, `tertiaryLabelColor`, `quaternaryLabelColor` (SwiftUI: `.primary`, `.secondary`, `.tertiary`, `.quaternary` foreground styles).
  - Backgrounds and lines: `separatorColor`, `windowBackgroundColor`, `controlBackgroundColor`, `underPageBackgroundColor`, `gridColor`, `textBackgroundColor`.
  - Accent and selection: `controlAccentColor`, `selectedContentBackgroundColor`, `unemphasizedSelectedContentBackgroundColor`, `alternatingContentBackgroundColors`.
  - Other: `findHighlightColor`, `linkColor`, `placeholderTextColor`, `keyboardFocusIndicatorColor`.
- The system colors were re-tuned in 2025 for Light, Dark and Increased Contrast to sit with glass [WWDC25 356].
- **Accent color:** the app accent applies only when the user's accent setting is *Multicolor*. Otherwise the user's choice replaces it everywhere except fixed-color sidebar icons.
- **Vibrancy:** on materials, use system vibrant colors (`.foregroundStyle(.secondary)` on `Material` is vibrant automatically). Inactive windows lose vibrancy.
- **Contrast** [HIG Accessibility]:
  - **4.5:1** for text up to 17 pt.
  - **3:1** for text 18 pt and up, or any bold text.
  - Test with Increase Contrast and Reduce Transparency on, and in macOS 27 at both ends of the glass transparency slider.

---

## 11. Typography

[HIG Typography]

- The macOS system font is SF Pro. **Default size 13 pt, minimum 10 pt.** macOS **doesn't support Dynamic Type**, and text styles are fixed.

| Style (SwiftUI `Font`) | Weight | Size / line height (pt) | Emphasized |
|---|---|---|---|
| `.largeTitle` | Regular | 26 / 32 | Bold |
| `.title` | Regular | 22 / 26 | Bold |
| `.title2` | Regular | 17 / 22 | Bold |
| `.title3` | Regular | 15 / 20 | Semibold |
| `.headline` | **Bold** | 13 / 16 | Heavy |
| `.body` | Regular | 13 / 16 | Semibold |
| `.callout` | Regular | 12 / 15 | Semibold |
| `.subheadline` | Regular | 11 / 14 | Semibold |
| `.footnote` | Regular | 10 / 13 | Semibold |
| `.caption` | Regular | 10 / 13 | Medium |
| `.caption2` | Medium | 10 / 13 | Semibold |

- Avoid the Ultralight, Thin and Light weights. Use Regular, Medium, Semibold and Bold. Build hierarchy from weight, size and color; `.fontWeight(.semibold)` is the "emphasized" variant.
- In 2025 typography became "bolder and left-aligned" in key moments such as alerts and onboarding [WWDC25 356].
- Use monospaced digits for changing numbers (`.monospacedDigit()`). Use `NSFont.menuBarFont` or `.menuFont` metrics if you draw text in menus or the menu bar.
- Window titles should be under 15 characters and never the app name [HIG Toolbars].

---

## 12. SF Symbols 7 (and 8 beta)

[HIG SF Symbols, updated July 2025]

- **Rendering modes:** monochrome, hierarchical, palette, multicolor (`.symbolRenderingMode(_:)`). Use hierarchical for depth and palette for explicit colors. Multicolor is for intrinsic meaning, like a green leaf or a red trash.slash.
- **Gradients (SF Symbols 7):** a linear gradient from a single color, in any mode, best at larger sizes: `.symbolColorRenderingMode(.gradient)`.
- **Variable value:** `Image(systemName:variableValue:)` is for a value that changes over time, such as signal, volume or progress. "Don't use it to communicate depth." Variable *draw* in SF7 draws the symbol partially along its path.
- **Weights and scales:** nine weights matched to SF Pro, and `.imageScale(.small | .medium | .large)` relative to cap height. Match symbol weight to the adjacent text weight.
- **Variants:** use outline in toolbars, lists and next to text; `.fill` for selection and emphasis; `.slash` for unavailable; enclosed (circle, square) for legibility at small sizes. Usually the container picks the variant (`.symbolVariant(_:)`).
- **Effects** (`.symbolEffect(_:options:value:)` and `.contentTransition(.symbolEffect(.replace))`):

| Effect | Use it for |
|---|---|
| Appear / Disappear | Showing or hiding a symbol |
| Bounce | A one-shot "it happened" |
| Scale | Persistent emphasis |
| Pulse | Ongoing activity (opacity) |
| Variable Color | Progress or activity, cumulative or iterative |
| Replace | down-up = state change; up-up = forward progress; off-up = next action |
| Magic Replace | The default between related symbols, such as a slash drawing on |
| Wiggle | Calling attention |
| Breathe | Ongoing status such as recording (opacity plus size) |
| Rotate | Work in progress |
| **Draw On / Draw Off** (SF7) | Progress, or reinforcing meaning |

- Apply effects judiciously, with a clear purpose, and avoid motion on frequent interactions.
- **Custom symbols:** start from the template, annotate layers, give alternative text, and use the component library for badges and enclosures.
- SF Symbols 8 and Icon Composer 2 shipped as betas at WWDC26 [Press].

---

## 13. App icons

[HIG App icons, updated June 2026]

- **Format:** macOS icons are **layered**, made in **Icon Composer** (Xcode). They have a background layer plus one or more foreground layers. The canvas is **1024×1024 px** and square; the system masks the corners.
- **Appearances:** default, dark, clear light, clear dark, tinted light, tinted dark. The system generates any appearance you don't provide.
- **Effects:**
  - The system adds specular highlights, refraction, translucency and shadows. **Don't bake in** highlights, shadows, bevels, blurs or glows.
  - Use groups in Icon Composer to apply effects at the group level.
  - In 27 the icons render sharper, and the directional specular highlights are removed [Press].
- **Layers:**
  - Use vector layers (SVG or PDF), with text converted to outlines. Use PNG for raster art or mesh gradients.
  - Keep foreground edges crisp, not feathered.
  - Vary opacity across layers for depth. Use a solid or gradient background set in Icon Composer.
  - Use **filled, overlapping shapes**. Keep primary content centered. Avoid text, photos, replicas of UI, and Apple hardware.
- **Legacy icons:** in Tahoe, legacy non-squircle icons get shrunk onto a gray squircle, the "icon jail" [Press: MacStories].
- **Keep the design consistent across appearances.** Don't swap elements between appearances. Base the dark icon on the light one.

---

## 14. Motion

[HIG Motion]

- Add motion purposefully. Keep it brief and precise, make it cancelable, and never make it the only carrier of information.
- Avoid motion on frequent interactions; system controls already animate.
- Glass handles its own motion (morphing, materializing, menus that "pop open" from their button). Presentations should **originate from their source control**, so sheets, menus and popovers spring from the button that opened them [WWDC25 219, 323, 356].
- Respect Reduce Motion: check `@Environment(\.accessibilityReduceMotion)` and replace movement with a fade.
- Animate size changes in popovers and panels so they don't look like a new view [HIG Popovers].
- On macOS 26 and later, SwiftUI synchronizes window-resize animation with content, with a resize anchor [WWDC25 256].

---

## 15. Panels, popovers and Settings

- **Panels** [HIG Panels]:
  - They float over the main window and give a short noun title.
  - Prefer simple adjustment controls such as sliders and steppers.
  - Hide them when the app is inactive.
  - No minimize button, and keep them out of the Window menu's document list.
  - Use a HUD only for media or full-screen contexts, keep it small, and use little color.
- **Popovers:**
  - For small amounts of information or functionality.
  - Show only one at a time, and never cascade them.
  - Auto-save on dismiss.
  - Don't use one for warnings; use an alert.
  - On macOS a popover can be detachable, becoming a panel.
- **Settings** (our workspace rule plus HIG): use a separate `Settings` scene with `.formStyle(.grouped)`. The menu item is *AppName ▸ Settings…* (⌘,).

---

## 16. How Apple's own Tahoe and Golden Gate apps look

- **Finder:**
  - Rounder window corners. The sidebar and toolbar are translucent, so the wallpaper and icons show through, while toolbar buttons stay more opaque.
  - Toolbar groups are always visible, not only on hover.
  - The bottom **status bar** holds only the item count and free space.
  - Folder colors follow the theme accent (eight folder colors plus custom).
  - In 27 the Finder icon reverted toward its pre-glass look [Press: MacStories, mjtsai].
- **Mail:**
  - Three columns, with the sidebar auto-collapsing in narrow windows.
  - A leading filter item, a flexible space, then a trailing group with **search plus compose**.
  - VIP uses a fixed yellow sidebar icon [WWDC25 323; HIG Sidebars].
- **Notes:** no window title when a single window is open, because the first line of the note supplies the context. Search sits in the trailing toolbar [HIG Toolbars].
- **Music, TV, Podcasts:**
  - Search is a sidebar item, used as a discovery area.
  - In 26, Music moved playback to a pill-shaped transparent bar at the bottom. It was criticized as hard to read over busy art, which is a warning against heavy transparency over media [Press].
- **System Settings:**
  - Search sits at the top of the sidebar and filters deep sections.
  - The detail panes are grouped forms.
  - In 27 it uses a hard scroll edge instead of the progressive blur [HIG Search; Press].
  - A new Menu Bar pane controls every extra.
- **Control Center and the menu bar:**
  - The menu bar is transparent by default.
  - Control Center is fully customizable from a widget-like gallery. Controls, including third-party ones via WidgetKit `ControlWidget`, can sit in Control Center panels or directly in the menu bar.
  - Volume and brightness HUDs now drop down beneath the Control Center icon [Press: MacStories].
- **Activity Monitor and Console:** these are table-heavy utilities. They keep the classic `Table` look with sortable, resizable columns and pinned headers under the toolbar, which calls for a **hard** scroll edge. Their toolbars hold segmented category controls (one glass piece), action buttons (one group) and trailing search. [Ours, inferred from the WWDC25 310 grouping rules and the hard-edge guidance for pinned headers. These apps are not described specifically in the sources.]
- **Xcode 27:** returned to a standard-height, customizable toolbar, "like a regular Mac app" [Press].

---

## Rules we should adopt

Each rule is testable by code review, previews, or a screenshot under Light, Dark, Increase Contrast and Reduce Transparency.

1. **No glass in the content layer.** `glassEffect`, `.buttonStyle(.glass)` and `.glassProminent` appear only on floating controls or navigation, never on list rows, cards or backgrounds. Content surfaces use `Material` or semantic background colors.
2. **No glass on glass.** No view inside a glass element applies another `glassEffect`. Overlays on glass use fills, opacity or vibrancy.
3. **Group nearby glass in a container.** Any two or more custom glass shapes in one stack are wrapped in a single `GlassEffectContainer`.
4. **Gate glass on availability, with a fallback.** Every glass call sits behind `if #available(macOS 26, *)` and falls back to a `Material` or bordered style on macOS 15. The fallback is rendered in previews.
5. **Use `Glass.clear` only over media,** paired with a dimming layer of about 35% black when the content is bright. Otherwise use `.regular`.
6. **No custom bar backgrounds.** No hand-drawn backgrounds, gradients or dividers behind the toolbar or under the title bar. Separation comes from the system scroll edge effect, with `.scrollEdgeEffectStyle(.hard, for: .top)` only for pinned headers or dense text.
7. **One scroll edge style per scroll view.** Soft and hard are never mixed, and every pane of a split view uses the same style.
8. **Toolbar groups.**
   - At most 3 groups, built with `ToolbarItemGroup` and `ToolbarSpacer`.
   - Never a text button grouped with a symbol button.
   - Non-interactive toolbar content uses `.sharedBackgroundVisibility(.hidden)`.
9. **One primary action per toolbar,** on the trailing side and prominent. All other toolbar symbols stay monochrome; `.tint` only for meaning.
10. **Toolbar commands also live in the menu bar.** Every toolbar action has a menu bar or `CommandMenu` equivalent with a keyboard shortcut.
11. **Window titles** are under 15 characters, never the app name, or empty when the content is self-titling.
12. **Corners and controls.**
    - Inner corners are concentric (`ConcentricRectangle` or `.rect(corners: .concentric)` with `.containerShape`), or capsules.
    - No hard-coded corner radius on any view that touches a window or panel edge.
    - No hard-coded control heights; size controls with `.controlSize`.
13. **Control prominence by style, not size.** At most 1–2 prominent buttons per view. The default action uses `.keyboardShortcut(.defaultAction)`, and destructive actions are never the default.
14. **Hit targets** are at least 20×20 pt, with 28×28 pt as the default for custom clickable views (check with a `.contentShape` audit).
15. **Text uses the built-in styles.**
    - Body is 13 pt, nothing below 10 pt, and no Light, Thin or Ultralight weights.
    - Hierarchy comes from weight and semantic color (`.secondary`, `.tertiary`), not ad-hoc font sizes.
    - Changing numbers use `.monospacedDigit()`.
16. **Only semantic colors** for text, separators, backgrounds and selection (no hex values in views). Accent color appears only on primary actions, selection and status. Text contrast is at least 4.5:1 below 18 pt.
17. **Sidebars.**
    - At most 2 levels.
    - Collapsible from a toolbar button and View ▸ Hide Sidebar.
    - Icons are SF Symbols following the accent color; fixed colors only where the color means something.
    - No `NSVisualEffectView` or extra material inside the sidebar, and nothing critical at its bottom.
18. **Rich hero content extends under the sidebar** with `.backgroundExtensionEffect()`, and text or controls are layered above the extended area.
19. **Search placement.** Search in a split-view window is `.searchable` on the `NavigationSplitView`, so it lands in the trailing toolbar. Use `.searchable(placement: .sidebar)` only when it filters the sidebar itself.
20. **Menu bar extras.**
    - Template-image or SF Symbol icon sized for the 24-pt menu bar.
    - Show a menu by default (`.menuBarExtraStyle(.menu)`); `.window` only when the job needs live data or richer controls.
    - All settings stay in the separate Settings window.
21. **Menu icons follow the 27 rule:** icons only on key actions, all or none within a group, standard symbols for standard actions. Default to title-only; opt in with `.labelStyle(.titleAndIcon)`.
22. **Symbol rendering and animation.**
    - Variable value only for changing quantities, hierarchical for depth, `.fill` only for selection or emphasis.
    - Every `.symbolEffect` has a stated purpose: bounce for done, pulse or breathe for ongoing, replace for a state change.
    - No repeating effects on idle UI.
23. **Motion respects Reduce Motion.** Every custom animation checks `accessibilityReduceMotion` and degrades to an opacity change. No animation blocks input.
24. **Inactive windows look inactive.** Custom chrome reads `@Environment(\.appearsActive)` and dims, and custom selection switches to its unemphasized style when the window is not key.
25. **App icon.** An Icon Composer `.icon` file with layered vector artwork on a 1024-px square canvas, with no baked-in shadows or highlights, and checked in default, dark, clear and tinted appearances.

## Sources

**HIG pages** (the `.md` variants were read on 2026-10-18):
- [materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [the-menu-bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [windows](https://developer.apple.com/design/human-interface-guidelines/windows)
- [sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [split-views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [lists-and-tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [search-fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [color](https://developer.apple.com/design/human-interface-guidelines/color)
- [typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [sf-symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [app-icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)
- [panels](https://developer.apple.com/design/human-interface-guidelines/panels)

The HIG has no standalone "inspectors" page; that guidance lives under the panels page and in the WWDC sessions.

**WWDC25:**
- [219 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [356 Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [323 Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [310 Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)
- [256 What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)

**WWDC26:**
- [269 What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)
- [289 Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/)
- [292 Design intuitive search experiences](https://developer.apple.com/videos/play/wwdc2026/292/)
- [250 Principles of great design](https://developer.apple.com/videos/play/wwdc2026/250/)

**API availability:** checked against `developer.apple.com/tutorials/data/documentation/...` for `glassEffect`, `Glass`, `GlassEffectContainer`, `ToolbarSpacer`, `sharedBackgroundVisibility`, `scrollEdgeEffectStyle`, `safeAreaBar`, `backgroundExtensionEffect`, `ConcentricRectangle`, `containerShape`, `ToolbarOverflowMenu` (not available on macOS), and `NSMenuItem.preferredImageVisibility` (macOS 27).

**Press:**
- [mjtsai.com 2026-06-09](https://mjtsai.com/blog/2026/06/09/) (macOS 27 Golden Gate roundup)
- [MacStories Tahoe review, p.2](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/2) and [p.3](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3)
- [iGeeksBlog macOS 27 redesign](https://www.igeeksblog.com/macos-27-liquid-glass-redesign/)
