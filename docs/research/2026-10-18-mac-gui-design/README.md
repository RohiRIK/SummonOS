# macOS GUI design research (2026-10-18)

Four parallel research passes, run after the first Summon Activity window was judged "looks like shit"
on a real Mac. The goal: raise the bar for every plugin's menu bar item, panel and window, and feed the
results into the `MacUX` skill. Each report cites its sources; claims marked *(observed)* or `[obs]` /
`[inferred]` / `[Ours]` were not fetched from a page and need checking before they become law.

| Report | What it covers | Became |
|---|---|---|
| [01-menubar-apps.md](01-menubar-apps.md) | Stats, CodexBar, Itsycal, Ice (code read), iStat Menus, Dato, Lungo, Fantastical, 1Password, Things, Raycast, CleanShot, Tailscale | `MacUX/MenuBarItem.md` |
| [02-hig-tahoe-golden-gate.md](02-hig-tahoe-golden-gate.md) | Current HIG text, Liquid Glass two-layer model, macOS 26 Tahoe and macOS 27 Golden Gate changes, type scale, SF Symbols 7, app icons | `MacUX/Windows.md`, `Principles.md` |
| [03-menubar-and-window-mechanics.md](03-menubar-and-window-mechanics.md) | `MenuBarExtra` limits, `NSStatusItem` + `NSPanel`, live status item, bringing a window to the front from an accessory app, Settings, chrome APIs, glass gating, upside-down text | `MacUX/MenuBarItem.md`, `Windows.md`, Gotchas |
| [04-activity-and-agent-ui.md](04-activity-and-agent-ui.md) | Console, Activity Monitor, Xcode reports, Linear, Things, Raycast, Superhuman, Tower, Warp, Cursor, Claude desktop, Codex, Conductor | `MacUX/ActivityFeeds.md` |

## The five findings that matter most

1. **Status lives in the chrome, not in cards.** Native windows show state in the toolbar, subtitle or a
   bottom strip, and show problems only when there are any. A grid of rounded tiles reads as a web
   dashboard (04 §1, §3).
2. **Glass is the control layer only.** Never on rows, cards or detail. Use system containers
   (`NavigationSplitView`, toolbar, `List`, `Form`) and get Tahoe and Golden Gate right for free; hand-drawn
   glass breaks when Apple changes the look, as it did between 26 and 27 (02 §1, §2).
3. **An accessory app's window opens behind other apps by design** (macOS 14+ cooperative activation).
   Switch to `.regular`, activate, open, then raise the window from `viewDidMoveToWindow`; fall back to the
   deprecated `activate(ignoringOtherApps:)` (03 §3).
4. **`MenuBarExtra(.window)` stops early.** No programmatic open, no right-click menu, no live label, no
   animated resize. A menu bar app that needs any of these uses `NSStatusItem` + a nonactivating `NSPanel`
   (03 §1, §2).
5. **A feed is a worklist, not a log.** Every row has a verb-first title, one primary action on ↵, a
   context menu and a ⌘K entry; undo scales from instant ⌘Z to a preview sheet that says what it cannot
   restore (04 §3).
