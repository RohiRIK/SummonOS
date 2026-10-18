# DesignPass Workflow

Take a macOS view from "works" to "looks like Apple shipped it". Recorded from the mac-network
panel: "looks like Windows 98" → "now it looks good" → tabs like CodexBar → "chef's kiss", in six
screenshot-driven passes on 2026-09-29.
Run it for a new screen, a redesign, or any UI complaint from the user.

## Step 1: Capture the complaint exactly

- Quote the user's words and look at their screenshot. Name each problem in one line:
  - **Style:** "Windows 98", "not nice", "want a background".
  - **Layout:** "cut off", "not the whole tab", overlapping rows.
  - **Behavior that looks like UI:** "Allow just toggled", names missing.
- Fix what they asked for. Do not also redesign parts they did not mention.

## Step 2: Diagnose before restyling

A UI complaint can be a layout bug or a data/permission bug in disguise. Check first:

- **Overlap or clipping** → sizing: panel root `fixedSize(vertical)`, no `Form` in a panel, ScrollView
  with `maxHeight` + `fixedSize` (`SKILL.md` Gotchas).
- **Missing data** → logs before code (`/usr/bin/log show … --predicate 'subsystem == "<bundle id>"'`),
  permission state (for Location, read `locationd` logs: `RegResult:<status>`, `InUse:0`).
- **A click did the wrong thing** → another view is on top of the target (overlap), not a broken action.

## Step 3: Find the Apple reference

Ask "which Apple UI does this resemble?" and copy its anatomy, not a generic web layout:

| Surface | Reference |
|---|---|
| Menu bar panel with a list | System Wi-Fi / Bluetooth menu (`MenuPanel.md`) |
| Live numbers, current device/connection | Control Center module (`MenuPanel.md` › Live-data module) |
| Several jobs in one panel | CodexBar tab switcher (`MenuPanel.md` › Everything in the panel) |
| Editing the app's job in a panel (IP settings) | A tab with `SettingsGroup` / `SettingsRow`, System Settings wording |
| The menu bar icon itself, right-click, ⌥-click | `MenuBarItem.md` |
| A full window (history, library, main app) | Mail / System Settings anatomy (`Windows.md`) |
| Events, history, running agent or job, undo | Console + Linear + Raycast grammar (`ActivityFeeds.md`) |
| App preferences, permissions, theme | Settings window (⌘,) + first-launch onboarding (`MenuPanel.md` › App settings and onboarding) |

**Check the reference apps already installed before inventing a pattern.** Look in `/Applications`
for a polished app that solves the same problem (for menu bar apps: CodexBar). If its source is public
and MIT or similar (`gh repo view <owner/repo> --json licenseInfo`, then read `LICENSE` itself: the API
can report none when the file exists), clone it to a scratch dir outside `plugins/`, find the view (`grep -rl` for
`Switcher`, `Settings`, `Card`), and adapt the pattern with an attribution comment and the upstream
notice in `THIRD_PARTY_NOTICES.md` (keep `LICENSE` pure MIT). No license means read-only: learn, never copy.

Fetch the HIG rule when unsure. Pages are JavaScript-rendered, so use the JSON endpoint:
`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`.

## Step 4: Plan components and every state

- Components first (`Components.swift`, feature modules like `ConnectionModule.swift`). Siblings
  share one component, so a fix lands everywhere.
- List every state, and give each one a `#Preview` with fake data before building:
  normal · empty · loading · error · permission-needed · alternate kind (Ethernet) · light · dark.
  The state the user hit (from their screenshot) is mandatory.

## Step 5: Build

- Style from `Principles.md` and `MenuPanel.md`: system fonts, semantic colors, `.quinary`/`.quaternary`
  fills, continuous corner radius, `.monospacedDigit()` on live numbers, health shown with color *and* text.
- Permission and error UI sits where the user looks (a banner or under the row), with the action on
  the right.

## Step 5b: Panel-level rules that screenshots caught

- More than one job in a panel → tabs (`TabSwitcher`), not extra windows. The user rejected a window.
- **Constant panel height across tabs:** tab content in a `ScrollView` with one fixed height (tallest
  normal tab). A panel that resizes per tab jumps, and can grow past the screen and clip its own top.
- Menu-density sizes: tab icons 11 pt, `.caption2` labels, 34 pt segments. Bigger reads as "too big".
- Groups with dividers: `.clipShape` the rounded group so dividers cannot run past the edge.

## Step 6: Render and review (max 3 cycles)

```bash
tools/render-previews.sh plugins/<name> <App>UI     # all previews → docs/previews/
```

Read every PNG. Check `Review.md` plus: alignment on one leading edge, consistent spacing (4/8/12),
nothing clipped, dark and light both correct, the user's state fixed.
Height check for tabbed panels (must print one value):
`sips -g pixelHeight docs/previews/PanelView-*.png | grep pixelHeight | sort -u`

Fix and re-render. After 3 cycles, stop and list what is still uncertain.

## Step 7: Verify in the real app

`scripts/check.sh`, relaunch the `.app`, confirm it runs. Previews cannot show window sizing, the menu
bar icon, or permissions. Ask the user to open it and send a screenshot, and say exactly what to look for.

**The user's screenshot is the ground truth.** Every pass on mac-network found something previews could
not: panel height jumps, clipped tops, dividers past the edge, icons too big, a Location permission
stuck at When-In-Use. Loop: user screenshot → Step 1 → fix → previews → relaunch → ask for the next
screenshot. Stop when the user approves; record the approval in `PROJECT-CONTEXT.md`.

## Step 8: Record it

In the same turn:
- Pattern that worked → `MenuPanel.md` or `Patterns.md`; mistake → `SKILL.md` Gotchas.
- The user's taste ("wants polished, not just functional") → workspace `tasks/lessons.md`.
- The agreed design reference and preview paths → the plugin's `PROJECT-CONTEXT.md`.
- Commit the previews and post `scripts/pr-report.sh`, so the PR shows the before and after.
