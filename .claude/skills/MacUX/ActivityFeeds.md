# Activity feeds, status, agent sessions, and undo

For any view that lists what happened (events, history, logs, sessions) or controls a long-running job
(an agent, a sync, a build). Distilled from Console, Activity Monitor, Xcode reports, Linear, Things,
Raycast, Superhuman, Tower, Warp, Cursor and the Claude desktop app:
`docs/research/2026-10-18-mac-gui-design/04-activity-and-agent-ui.md`.

## Why feeds look bad

1. Every event has the same weight: a crash looks like a toggle.
2. Dashboard tiles on top ("3 sessions", "0 problems").
3. Colour as decoration: rows tinted by kind.
4. No verbs: rows you can only read.

## Hierarchy, top to bottom

1. **Needs attention**, only when non-empty (crash, waiting for approval, safety net off). Never an
   "All good" card; calm is the absence of a banner.
2. **Live**: the running job as one pinned row: live indicator, elapsed time ticking
   (`TimelineView(.periodic(from:by: 1))`, `.monospacedDigit()`), one current-step line that is *replaced*,
   not appended ("Editing App.swift…"), Stop (⌘.) and Open.
3. **History**, newest first, sticky day headers: Today, Yesterday, weekday this week, then date. Inside a
   day show clock times; hover shows the full timestamp (`.help`).
4. **Ambient status in the chrome**: subtitle, toolbar chip or bottom strip ("Idle · Safety net on · 42 checkpoints").

## Row anatomy

```
[16 pt symbol]  Verb-first title, ≤ 60 chars                    11:42
                secondary: project · source · counts      [hover: ↺ ›]
```

- 28 pt for one line, 44 pt for two; ≥ 12 rows visible in a 600 pt window. `List` inset style, no borders,
  no row backgrounds by kind.
- Colour only on the leading symbol, and every colour pairs with a **unique shape** (passes a greyscale
  screenshot): running `circle.dotted` (accent) · needs you `hand.raised.fill` (orange) · done
  `checkmark.circle` (secondary) · failed/crash `xmark.octagon.fill` (red) · checkpoint `bookmark` · setting
  `slider.horizontal.3` · revert `arrow.uturn.backward` (accent) · stale `clock.badge.exclamationmark` (orange)
  · safety net off `shield.slash` (orange).
- Human titles ("Turned off Dock autohide"), never raw keys or JSON; those go in the inspector.
- Untrusted strings (process names, prompts, paths) through a sanitiser that strips bidi controls,
  zero-width and control characters and caps combining marks; render with `Text(verbatim:)`,
  `.lineLimit(1)`, `.truncationMode(.middle)`. Hide no-op events (an undo that changed nothing).
- Every row: a primary action on ↵, a context menu, and the same actions in a ⌘K panel that shows each
  shortcut; destructive last, below a divider. Hover reveals at most 2 inline icon buttons.

## Grouping

Sessions are collapsible groups (Xcode reports) holding their checkpoints and changes; an error inside marks
the header. Consecutive same-kind events outside a session collapse ("5 settings changed" ▸).
Scopes (All · Needs Attention · Sessions · Settings · Crashes) on ⌘1…⌘5; search on ⌘F with tokens.

## Job states

`starting, running, needsYou, stale, completed, failed` (Linear's model). Stale = "running" but no event for N
minutes: secondary orange "No activity for 6 min", not red. Live steps read "Searching…" → "Searched".
Acknowledge a start within 100 ms (icon flips to starting before the job emits anything).
Notify (system banner) only on **completed, needsYou, failed**, and only when the window is not key.

## Undo ladder

1. Last small change: instant ⌘Z, toast with Redo and a visible countdown (≥ 5 s, pauses on hover).
2. A checkpoint or file revert: a **preview sheet**: what will change (counts), what is *not* covered
   (for Claude Code: Bash-made changes, most subagent edits, outside edits), button named verb + count
   ("Restore 4 Files"), Cancel is default. Offer Show Diff first.
3. A whole session: the same sheet listing its checkpoints.
4. A revert is its own event and can be undone. An item whose snapshot expired keeps a disabled Undo with
   the reason in its tooltip. Never "Are you sure?".

## Empty states

`ContentUnavailableView`: neutral symbol, one sentence, at most one action. Search: `.search(text:)`.
An empty "Needs attention" scope is one secondary line, "Nothing needs you".

## Keyboard map

↑↓ (J/K) move · ↵ primary · Space quick look · ⌘Z undo last · ⌘⌫ revert selected (sheet) · ⌘K actions ·
⌘F search · ⌘1–5 scopes · ⌘N / global hotkey prompt bar · ⌘. stop · ⌘, Settings · ⌘/ shortcuts.

## Prompt bar (asking an agent)

A floating panel on a global hotkey (Things Quick Entry, ChatGPT companion): one field, a project chip, a mode
chip (permission mode, especially Bypass, always visible), ↵ runs, Esc dismisses and returns focus to the
previous app. The same bar may sit at the bottom of the window; one code path behind both.
