# macOS UX principles

## What "native" means

- Looks like Control Center, Wi-Fi menu, System Settings. Users already know those.
- Instant: panel opens with cached data, then refreshes. Never a blank panel while loading.
- Quiet: no splash, no badges for nothing. Onboarding only when the app cannot work without a permission (`MenuPanel.md` › App settings and onboarding). Otherwise ask for permission when the user hits the feature that needs it, and say why.
- Reversible: destructive or system-changing actions (static IP, forget network) show what will change and need one explicit confirm.
- Honest: show the real state. If a value is unknown, show `--` or a reason, never a fake value.

## Layout

- Menu bar panel width: 300-360 pt. One column.
- Spacing scale: 4, 8, 12, 16, 20. Panel padding 12-16. Row height ~28-32 (like the system Wi-Fi menu).
- Sections separated by a `Divider()` with 8 pt vertical padding, or a small caps-free secondary header (`.font(.subheadline).foregroundStyle(.secondary)`).
- Align on a leading edge. Icons in a fixed 16-20 pt column so labels line up.
- Click targets: 28×28 pt default, 20×20 pt minimum for custom clickable views.
- Corners: an inner rounded shape is concentric with its container (radius = outer − padding); never a hard-coded radius on anything touching a window edge.
- Primary action bottom-right in forms; Cancel to its left. Use `.keyboardShortcut(.defaultAction)` and `.cancelAction`.

## Typography

- System font only (SF Pro). Semantic styles: `.headline` for panel title, `.body` for rows, `.caption`/`.footnote` for detail.
- macOS sizes are fixed (no Dynamic Type): `.title` 22, `.title2` 17, `.title3` 15, `.headline` 13 bold, `.body` 13,
  `.callout` 12, `.subheadline` 11, `.footnote`/`.caption` 10. Nothing under 10 pt; no Light/Thin weights.
  At most 3 sizes per panel.
- Hierarchy through weight and `.secondary`/`.tertiary` foreground, not through size jumps.
- `.monospacedDigit()` on any number that changes. `.monospaced()` for IPs and MACs only if they are aligned in a list.
- Buttons and menu items: title case ("IP Settings…", "Forget This Network…"), as macOS does. Field labels and help text: sentence case ("Subnet mask").

## Color and materials

- Semantic colors: `.primary`, `.secondary`, `.tint`, `Color(nsColor: .controlBackgroundColor)`. Test light, dark, Increase Contrast, Reduce Transparency.
- Accent color follows the user's system accent. Do not override the tint globally.
- Status colors: green = good, yellow/orange = degraded, red = failed. Always pair color with an icon or text (color-blind users).
- macOS 26 Liquid Glass: only on floating controls and navigation (`.glassEffect()`, `GlassEffectContainer` to group). Never on content: the HIG says standard materials for the content layer. A menu bar panel already sits on the system material; add none.

## SF Symbols

- Use variable value for levels: `Image(systemName: "wifi", variableValue: strength)`.
- Use `.symbolRenderingMode(.hierarchical)` for depth, `.palette` only for status.
- Animate state changes with `.contentTransition(.symbolEffect(.replace))`, and activity with `.symbolEffect(.pulse)` / `.variableColor`.
- Browse names with the SF Symbols app. Never invent a symbol name; a wrong name renders nothing.

## Motion

- Default `.animation(.snappy, value:)` / `.smooth`. Durations 150-250 ms.
- Animate state transitions, not idle decoration.
- Respect Reduce Motion: `@Environment(\.accessibilityReduceMotion)`; swap slides for fades.
- Screen changes inside a panel (list to settings): `.transition(.move(edge: .trailing).combined(with: .opacity))`.

## Keyboard

- Every action has a key. Show it (`.help("Refresh (R)")`, or a trailing `Text("R").foregroundStyle(.tertiary)`).
- Esc goes back one level, then closes.
- Arrow keys move through lists; Return activates. Use `List` with selection or `.focusable()` + `.onKeyPress`.
- Tab order follows visual order.

## Accessibility

- Icon-only button: `.accessibilityLabel("Refresh")` + `.help("Refresh")`.
- Combine row parts: `.accessibilityElement(children: .combine)`.
- Dynamic values: `.accessibilityValue("72 percent")`.
- Test with VoiceOver (Cmd-F5) once per plugin.

## Feedback states

Every data view designs all five: loading (first load only), content, empty, error (with retry), permission-needed (with a button that opens the right System Settings pane).

## Rules from Glaze's design system (adapted to SwiftUI)

- **Flat surfaces, separation by structure.** Group with spacing, section headers and dividers, not
  cards, borders, or shadows. No "web card" styling.
- **System components first.** Use the SwiftUI control that exists (`Toggle`, `Picker`, `Table`,
  `List`, `Form` in a Settings window, `LabeledContent`) before custom markup. Customize by wrapping, not
  by re-drawing.
- **Semantic roles only.** Text: `.primary` > `.secondary` > `.tertiary` > `.quaternary` by emphasis.
  Fills: `.quaternary` for subtle control fills, `Color(nsColor: .selectedContentBackgroundColor)` for
  selection. Separators: `Divider()` / `.separatorColor`. Never raw palette colors.
- **One prominent action per screen or dialog** (`.borderedProminent` / `.keyboardShortcut(.defaultAction)`).
- **Settings live in the Settings window** (⌘,) with grouped `Form` rows. No Done button: the window's
  close button closes it. Panels hold only quick, in-context edits.
- **Siblings share one implementation.** Rows, tabs, or buttons in one group render through one
  component; fix the shared component, never fork a one-off copy.
- **Style exactly what was named.** "Make the count bold" changes the count's own view, not its row.
- **Design references are requirements.** When the user gives a screenshot or mockup, match its
  regions, hierarchy, labels (verbatim) and states. Ask only when it leaves a real choice open. Record
  the agreed reference path in the plugin's `PROJECT-CONTEXT.md`.
- **Loading without layout shift.** Placeholder views with the final size (`.redacted(reason: .placeholder)`),
  never an empty view that pops in later.
- **Focus is visible.** Every interactive element shows keyboard focus; do not hide focus rings except on
  a container that manages focus itself.
- **Frosted surfaces come from the window**, not from blurring views (`.background(.ultraThinMaterial)`
  on a whole panel is wrong in a menu bar extra: the system already provides the material).
