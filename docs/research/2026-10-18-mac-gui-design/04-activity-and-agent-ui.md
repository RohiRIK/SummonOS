---
type: Research
title: Activity feeds and agent UI
description: "How the best apps show activity timelines, status and agent control, applied to Summon."
tags: [research, design, summon]
created: 2026-10-18
---

# 04 — Activity feeds, timelines, status and agent control: what the best apps do

Research for **Summon**, a native macOS menu bar app that controls Claude Code on the Mac. It has an
activity timeline (settings changed via CLI, checkpoints, agent sessions start/end, crashes), a status
overview (agent idle/running, safety net, problems), undo per change or per session, and a "run agent"
prompt bar. The current window "looks like shit". This report pulls patterns from apps that get this
right and ends with testable rules and three original layouts.

Date: 2026-10-18. Sources are listed per section; claims marked *(observed)* come from hands-on
knowledge of the shipping apps, not a fetched page.

---

## 1. The core diagnosis: why activity windows look bad

Most "activity" windows that look bad share four faults:

1. **Every event is shown at the same weight.** A crash, a settings toggle, and "session ended
   normally" all get the same row, the same icon size, and the same color. Good feeds (Linear Inbox,
   Warp's notification mailbox, Console's Errors and Faults view) split *what needs me* from
   *what happened*.
2. **Dashboard cards on top.** Rows of rounded tiles with big numbers ("3 sessions", "0 problems")
   read as a web admin panel. Native Mac apps put status into the *chrome*: title bar subtitle,
   toolbar items, a sidebar badge, a single banner only when something is wrong.
3. **Color as decoration.** Tinted backgrounds on every row type. Things 3 is about 95% neutral and
   uses color only for meaning (yellow Today, red deadline, green done) ([Things design guide](https://blakecrosley.com/es/guides/design/things)).
4. **No verbs.** A feed you can only read is a log. The best feeds are worklists: every row has
   one primary action on Return (Raycast), a context menu, and a ⌘K panel listing the rest with shortcuts.

---

## 2. App-by-app findings

### macOS Console.app
- Layout: sidebar (devices; Crash Reports, Spin Reports, Log Reports), message list on top, detail of
  the selected message below. A new window does not stream until you press **Start streaming**, and
  **Pause** freezes the list for reading ([Intego Console guide](https://www.intego.com/mac-security-blog/how-to-use-the-console-app-for-troubleshooting); [Apple Console guide](https://support.apple.com/guide/console/cnsl35710)).
- Severity is shown as a **small colored dot** in a narrow column: yellow for error, red for fault.
  The row itself stays neutral.
- One-click **Errors and Faults** scope next to **All Messages**, plus saved searches sitting beside them.
  Search uses **tokens** (`Process: x`, `Message Type: Error`) with Contains / Does not contain.
- Crash reports are a separate source, not interleaved with streaming chatter.
- **Lesson for Summon:** severity as a 6–8 pt dot or a symbol tint in a fixed column; scopes as a
  segmented control (All / Needs attention / Agent / Settings); token search; crashes get their own
  scope *and* surface in "Needs attention".

### Activity Monitor (Tahoe) *(observed)*
- Tabs as a segmented control in the toolbar (CPU / Memory / Energy / Disk / Network), a dense
  sortable table, and a **summary strip at the bottom** of the window (System / User / Idle,
  plus a small live graph). Status lives at the *bottom edge*, small and calm, not as cards on top.
- Toolbar: Stop (⊗), Inspect (ⓘ), more actions (⋯), search. Destructive action (Force Quit)
  is confirmed with a sheet naming the process.
- **Lesson:** a status strip or footer works better than a card grid. Numbers in tabular digits,
  labels in secondary color.

### Xcode report navigator *(docs + observed)*
- Reports listed **By Group** or **By Time**; each build or test run is a row with a status
  glyph (green check, red ✕, yellow ⚠) and a relative timestamp. Selecting it opens the log in the editor
  with All / Recent and All Messages / All Issues / Errors Only filters plus free-text search
  ([Xcode help](https://help.apple.com/xcode/mac/current/en.lproj/dev21d56ecd4.html)).
- Log lines are **collapsible steps** with a duration on the right. Errors bubble up to the step header.
- **Lesson:** sessions are the natural "build" unit. A session row expands to its steps
  (prompts, tool calls, checkpoints), and an error inside a session marks the session header.

### Time Machine / Versions ("Browse All Versions")
- The current document and past versions are shown side by side, with arrows or a timeline to step
  through them. **Restore** replaces the current document. You can also copy parts out of an old
  version without restoring ([MacMost](https://macmost.com/accessing-document-history-on-your-mac.html); [Apple Pages help](https://help.apple.com/pages/mac/5.6/en.lproj/tan7f1de6ec5.html)).
- **Lesson:** before reverting, show *what will change*: a before/after or a file diff summary.
  Also offer a non-destructive option (here, "Restore as copy" or "Show diff").

### Claude Code checkpoints (the thing Summon wraps)
- A checkpoint is created before each prompt that starts a turn. The last 100 are kept, and snapshots
  are cleaned up after about 30 days. `/rewind` offers **Restore code and conversation / Restore conversation
  / Restore code / Summarize from here / Summarize up to here / Never mind**
  ([Claude Code checkpointing](https://code.claude.com/docs/en/checkpointing)).
- Limitations Summon *must* show honestly: Bash-made file changes are not tracked, subagent edits are
  mostly not restored, external and other-session edits are not tracked, symlinks and hard links are skipped.
- **Lesson:** an undo UI must say what it *cannot* undo. A "Safety net" status should show
  coverage: "Checkpoints on · 42 kept · 3 Bash changes not covered".

### Proxyman
- Three panes: source list of apps and domains (with **Pin**), request list, inspector with tabs.
  Multiple filters by URL, method, status ([Proxyman getting started](https://proxyman.com/posts/2019-06-14-getting-started-with-proxyman)).
  Status codes are shown as colored text in a column *(observed)*, not as row tints.
- **Lesson:** pinning a source (a project folder) and scoping the feed to it beats one global stream.

### Linear (Inbox + agent sessions)
- Inbox splits **Priority** from **Other**. Shortcuts: J/K to move, U for read/unread, H to snooze,
  ⌫ to delete, ⇧⌫ to delete all read, ⌘F for quick search across type, assignee, project
  ([Linear Inbox docs](https://linear.app/docs/inbox)). Display options: show unread first, show snoozed, grouping.
- Linear's **Agent Interaction Guidelines**: an agent must make its state readable at a glance
  (processing, awaiting input, acting, done), keep its reasoning and tool use inspectable, give
  "immediate, but unobtrusive, feedback" when invoked, and leave a human accountable
  ([AIG](https://linear.app/developers/aig.md)).
- Agent session model: activity types `thought`, `elicitation`, `action`, `response`, `error`. Session states:
  `pending`, `active`, `awaitingInput`, `complete`, `error`, `stale`. Actions read as a **verb pair**:
  "Searching…" becomes "Searched" with its parameter and result. Ephemeral activities are replaced by the next one.
  An agent must acknowledge within 10 s or it is marked unresponsive ([Linear agent interaction](https://linear.app/developers/agent-interaction)).
- **Lesson:** adopt Linear's six-state model for Summon sessions, including **stale** (it should be
  running but has gone quiet). Use present-progressive → past tense for live steps, and give the
  currently running step a single ephemeral line.

### Things 3
- Rows: a leading control, a title, then quiet metadata (project, deadline badge, tag). Hairline
  separators, generous padding, color only for meaning. Logbook groups completed work by date.
  Quick Entry is a floating ~500 pt translucent panel: Return creates, Esc dismisses. Completing a task
  plays a ~500 ms animation: the circle fills, a check springs in, the row slides out
  ([Things design guide](https://blakecrosley.com/es/guides/design/things)).
- **Lesson:** "Today / Yesterday / Earlier this week" headers; a quick-entry prompt bar with the same
  Return/Esc grammar; one satisfying confirmation motion when an undo completes.

### Raycast
- Rows: a leading icon (app icon or SF Symbol), a bold title, a muted subtitle, and trailing accessories
  (shortcut badge, status symbol, date). Short section headers. The list ends with an **action bar
  footer** showing the primary action (↵) and "Actions ⌘K". The ⌘K panel lists every action with its
  right-aligned shortcut, has its own search field, and puts destructive actions last behind a divider
  ([Raycast action panel](https://manual.raycast.com/action-panel); [Raycast design guide](https://blakecrosley.com/fr/guides/design/raycast)).
- Empty state: a centered neutral icon, a one-line message echoing the query, one suggested action.
- **Lesson:** this is the best fit for Summon's grammar. ↵ = primary (open session / show diff),
  ⌘K = all actions, ⌘Z = undo selected, with the footer always naming both.

### Superhuman
- Speed is the product: 100 ms reads as instant, and internal targets are 50–60 ms. UI is optimistic,
  and "undo is the safety net, not loading spinners". The undo toast has a **visible countdown** and
  its own key (Z). ⌘K always shows each command's shortcut so users graduate to the keys. ⌘/ lists shortcuts
  ([Superhuman design guide](https://blakecrosley.com/guides/design/superhuman); [Command palette essay](https://blog.superhuman.com/how-to-build-a-remarkable-command-palette/)).
- Palette principles: available everywhere with one shortcut that also closes it, every command
  in one place, fuzzy matching with aliases, context-ranked results.

### Tower and GitHub Desktop
- Tower: **⌘Z undoes most Git actions** (discard, stage, commit, branch delete, merge, rebase,
  stash) and ⇧⌘Z redoes ([Tower undo](https://www.git-tower.com/features/undo)). Undo is a global verb, not a per-screen feature.
- GitHub Desktop: after a commit, an **Undo** button sits beside the latest commit at the bottom of the
  Changes sidebar. It is only offered for the most recent, safely reversible thing
  ([GitHub Desktop docs](https://docs.github.com/en/enterprise-cloud@latest/desktop/managing-commits/undoing-a-commit-in-github-desktop)).
- **Lesson:** ⌘Z in Summon undoes the last Summon-visible change. Older changes get an explicit
  "Revert…" with a preview. Offer redo where the operation allows it.

### Warp (agent mode / notifications)
- Each agent tab shows a status icon: **working, blocked, completed, errored**. An unread badge shows on
  tabs that need attention. A **notification mailbox** (bell) has All / Unread / Errors filters,
  "Mark all as read", and arrow/Enter/Esc navigation. In-app toasts pause on hover, and at most two show at
  once. Desktop notifications appear only when the app is in the background. Triggers are exactly three:
  **Complete, Request (blocked on input or approval), Error** ([Warp agent notifications](https://docs.warp.dev/agents/capabilities/agent-notifications/)).
- **Lesson:** notify only on the three transitions. Everything else lives silently in the feed.

### Cursor background agents
- The Agents sidebar shows, for each agent, its **current step, elapsed time, and live log**. A status bar
  icon is used for monitoring, and a status bar notification appears on finish
  ([Cursor 3 guide](https://tutorials.technology/tutorials/cursor-ai-v3-complete-guide-2026.html)).
- A user request for color-coded states (running blue, needs input yellow, done green, plus error)
  includes "accessible for color-blind users". Another thread complains that the dock/menu-bar badge count doesn't match the
  sidebar's needs-attention count ([forum request](https://forum.cursor.com/t/color-the-agent-chat-background-by-status-running-needs-input-done/168083); [badge mismatch](https://forum.cursor.com/t/dock-menu-bar-badge-count-does-not-match-agents-sidebar-needs-attention-glass/168982)).
- **Lesson:** pair every state color with a distinct symbol shape. The menu bar badge and the window's
  attention count must come from the *same* computed value.

### Claude desktop app / Claude Code desktop
- A sidebar of active and recent sessions grouped by project, filterable by status or environment
  (⇧⌘F). Sessions auto-archive when their PR merges, with an "Archived" filter. ⌘1–9 switch sessions,
  ⌘K is the command palette, ⌘/ lists shortcuts. The permission mode indicator sits bottom-left, and a usage
  popover badge sits top-right ([Claude Code desktop redesign](https://pasqualepillitteri.it/en/news/866/claude-code-desktop-redesign-parallel-sessions)).
- **Lesson:** Summon should *not* duplicate the chat UI. It is the control tower: state, history,
  and recovery. Deep-link "Open in Claude" for the conversation itself. Show permission mode as a quiet
  chip, because "Bypass permissions" is a safety fact.

### Codex app and Conductor
- Codex (now on learn.chatgpt.com) has a chat/project sidebar, Quick chat next to New chat, and automations
  with a review queue for unattended runs ([Codex app](https://learn.chatgpt.com/docs/app);
  [automations / review queue write-up](https://codex.danielvaughan.com/2026/04/08/codex-desktop-automations/)).
- Conductor gives each parallel agent a workspace (a worktree) created from a branch, PR, or issue (⇧⌘N),
  a Diff Viewer (⇧⌘D), and a Checks tab (git status, CI, comments, todos). Workspaces are archived after merge
  ([Conductor docs](https://www.conductor.build/llms-full.txt)).
- **Lesson:** "review queue" framing. Finished agent runs that changed files land in a *To review* group
  until the user opens or dismisses them. That is a sharper concept than "Ended".

### ChatGPT Mac app companion window
- ⌥Space opens a floating companion window that stays in front while you work elsewhere
  ([AlternativeTo](https://alternativeto.net/news/2024/8/openai-introduces-handy-companion-window-for-chatgpt-on-macos);
  [MacRumors how-to](https://macrumors.com/how-to/use-chatgpt-app-for-macos-mac)).
- **Lesson:** Summon's prompt bar should be summonable globally (user-configurable, avoid clashing with
  ⌥Space/⌘Space), open as a small floating panel, and return focus to the previous app on Esc.

### Tahoe / macOS 27 chrome context
- Critics say Tahoe toolbars put grey glass platters on grey backgrounds, with harsh shadows that make controls
  float ([Benjamin Mayo](https://bzamayo.com/tahoe-toolbars)). macOS 27 restores clearer
  toolbar separation, full-edge sidebars, and colored sidebar icons ([Michael Tsai roundup](https://mjtsai.com/blog/2026/06/09/golden-gate-sidebars-and-toolbars/)).
- **Lesson:** use system `NavigationSplitView`, a toolbar, and `List` and get the glass for free. Don't hand-roll glass
  cards, don't stack custom shadows, and don't put glass on content rows.

---

## 3. Synthesis by question

### Information hierarchy (what's at the top)
Across Console, Linear, Warp, and Activity Monitor, the order is:
1. **Exception first, if any:** one banner or pinned group, "Needs attention" (crash, agent waiting for
   approval, safety net off). It is absent when everything is fine. Never show a green "All good" card that takes
   space. Use a quiet line or nothing.
2. **Live:** a running session as a single pinned row with a live indicator.
3. **History:** the chronological feed grouped by day, newest first.
4. **Ambient status** in the chrome: window subtitle ("Idle · Safety net on"), a toolbar chip, or a bottom
   strip à la Activity Monitor.

### Row anatomy
`[symbol 16pt, tinted by kind] Title (verb-first, ≤ 60 chars)        [trailing: time]`
`                               secondary line: project · scope · detail      [hover: actions]`
- Title states the change in human words: "Turned off auto-compact", "Session ended: 14 files changed".
  Not "settings.update key=autoCompact".
- Secondary line in `.secondary`: project folder name, source (CLI / Summon / agent), counts.
- Trailing: time. Relative within ~24 h ("2 min ago", "11:42"). Inside day groups, show a clock time ("11:42") because the header
  already gives the day. Hover tooltip shows the absolute ISO-ish timestamp. Use `Date.RelativeFormatStyle` / `RelativeDateTimeFormatter`
  ([Apple RelativeFormatStyle](https://developer.apple.com/documentation/foundation/date/relativeformatstyle.md)).
- Hover reveals 1–2 inline icon buttons (Undo, Show diff). The same actions live in the context menu and ⌘K.
- Height: 28 pt single-line or 44 pt two-line on macOS. Hairline separators or none, as in system `List` inset style.

### Grouping
- Day sections: Today / Yesterday / weekday name for this week / date. Sticky headers.
- Inside a day, **sessions are collapsible groups** (Xcode-style). Settings changes made outside a session
  are top-level rows. Consecutive same-kind events collapse ("5 settings changed via CLI" ▸).
- Optional view toggle: **By Time | By Session | By Project** (Xcode's By Group / By Time).

### Density
Mac users expect density. The best feeds fit about 12–18 rows in a 600 pt-tall window. The menu bar panel shows
at most 5–6 recent items plus the live row. Use the system body font (13 pt) and 11 pt secondary. Never make a
row taller to fit a card border.

### Currently running agent
- Pinned to top as a single row with a **live indicator**: a small pulsing dot, or the
  `ProgressView().controlSize(.small)` spinner, plus **elapsed time ticking** in monospaced digits (`TimelineView(.periodic)`).
- Below the title, a single **ephemeral current-step line** (Linear's model): "Editing Sources/App.swift…",
  replaced as steps arrive. Streaming text never scrolls the whole feed.
- Inline controls: **Stop** (⌘.) and **Open**. When waiting for approval, the row turns to the
  "needs you" state (orange symbol `hand.raised.fill`) with **Approve / Deny** or "Open to answer".
- Menu bar icon: animate subtly or swap the symbol variant while running. Add a badge dot only for "needs you".
- **Stale**: after N minutes with no events while "running", show "No activity for 6 min" in secondary
  orange text, not red.

### Undo / revert offered safely
Ladder (from [SaaS UI patterns](https://www.saasui.design/blog/saas-destructive-actions-confirmation-ux-patterns) + Superhuman + Tower):
1. **Last small change** (a setting): instant ⌘Z plus a toast "Turned auto-compact back on · Redo"
   with a visible countdown. No dialog.
2. **A checkpoint or file revert:** a sheet with a **preview**: files that will change (+/- counts), what
   is *not* covered (Bash changes, subagent edits), and buttons named by verb: "Restore 4 Files" (default:
   Cancel). Offer "Show Diff" first.
3. **A whole session:** the same sheet, listing the session's checkpoints. Default selection is "before this session".
   Say whether the conversation is also rewound.
4. **Revert is itself an event** in the feed and is undoable ("Reverted session 'Fix tests' · Undo").
- Never auto-focus the destructive button. Never say "Are you sure?". Name counts.
- Disable or explain undo when snapshots are gone (the ~30-day cleanup): show the row with "Can't restore:
  snapshot expired".

### Status without a web dashboard
- Use the **chrome**: window subtitle, a toolbar chip, a sidebar badge, a bottom summary strip.
- When a status needs space, use a **grouped Form-style section** (`.formStyle(.grouped)`) or a single
  `GroupBox`, not a 3×2 tile grid. Each status is one line: SF Symbol + label + value + optional fix button
  ("Safety net · On · 42 checkpoints"; "Problems · 1 crash today › Show").
- Big numbers are fine only in a popover or Inspector. Avoid them as the first thing on screen.

### Filtering and search
- A scope segmented control (All · Needs Attention · Sessions · Settings · Crashes), à la Console and Warp.
- `.searchable` with **tokens** (`project:`, `kind:`, `source:`) and suggestions. ⌘F focuses search, Esc clears.
- Saved scopes optional, as with Console's saved searches.

### Empty states
- `ContentUnavailableView` with a neutral SF Symbol, one sentence, and one action. Examples:
  "No activity yet. Changes and agent sessions will appear here." [Run Agent…]. For a search:
  `ContentUnavailableView.search(text:)`.
- "Needs attention" empty: no empty state at all; the scope simply shows "Nothing needs you" in secondary text.

### Keyboard-first
- ↑/↓ (and J/K) move. ↵ runs the primary action. Space opens Quick Look-style detail. ⌘Z undoes the last change. ⌘⌫ reverts the selected item
  (with sheet). ⌘K opens actions. ⌘F searches. ⌘1–4 switch scopes. ⌘N or a global hotkey opens the prompt bar. ⌘. stops the agent.
  ⌘, opens Settings. ⌘/ or the Help menu shows shortcuts.
- Every shortcut is visible somewhere: menus, the ⌘K panel, the footer hint, tooltips.

### Command bar / prompt bar
- Floating panel (Things Quick Entry / ChatGPT companion / Raycast): one text field, a project picker
  chip, a mode chip (permission mode), ↵ runs, ⌘↵ runs in the background, Esc dismisses and returns focus.
- Acknowledge within 100 ms (Linear's "immediate, unobtrusive feedback"): the panel closes and the menu bar
  icon switches to running at once, before the agent emits anything.

### Color and iconography for event kinds
Neutral rows; color only on the leading symbol, and each color paired with a unique shape:

| Kind | SF Symbol | Tint |
|---|---|---|
| Agent running | `circle.dotted` animated / spinner | accent |
| Needs you (approval/input) | `hand.raised.fill` | orange |
| Session completed | `checkmark.circle` | secondary (green only if it changed files) |
| Session failed / crash | `xmark.octagon.fill` | red |
| Checkpoint | `bookmark` / `flag` | secondary |
| Setting changed | `slider.horizontal.3` | secondary |
| Revert/undo | `arrow.uturn.backward` | blue/accent |
| Stale | `clock.badge.exclamationmark` | orange |
| Safety net off | `shield.slash` | orange |

Status colors follow semantic system colors (green / orange / red), as Raycast and Console do.

---

## Rules we should adopt

1. The Activity window has **no card grid**. Status appears in the window subtitle and toolbar, plus at most one
   grouped status section; a reviewer can count zero `RoundedRectangle` tiles in the main view.
2. "Needs attention" content renders **only when non-empty**. With no problems, no banner or "all good" card takes vertical space.
3. A running session is **pinned above** the day-grouped history and shows a live indicator, elapsed time
   (monospaced digits, ticking every second), and one ephemeral current-step line.
4. Session state uses exactly these values: `starting, running, needsYou, stale, completed, failed`. Each has
   a **unique SF Symbol shape**, not just a color (grayscale screenshot test passes).
5. Row backgrounds are never tinted by event kind. Color appears only on the leading symbol and status text.
6. Rows are ≤ 44 pt tall (two lines) or 28 pt (one line). The window at 600 pt height shows ≥ 12 rows.
7. Titles are verb-first human sentences, ≤ 60 characters. Raw keys and JSON appear only in the detail/inspector.
8. History is grouped by day with sticky headers (Today, Yesterday, weekday, date). Times inside a group are
   clock times. Hovering any time shows the full absolute timestamp.
9. Sessions are collapsible groups containing their checkpoints and changes. An error inside marks the session header.
10. Every row has a primary action on ↵, a context menu, and an entry in the ⌘K action panel. Each action shows its
    shortcut. Destructive actions come last, below a divider.
11. ⌘Z undoes the most recent reversible change instantly and shows a toast with Redo and a visible countdown (≥ 5 s, paused on hover).
12. Reverting a checkpoint or session always opens a **preview sheet** listing affected files with counts and what is
    *not* covered (Bash, subagent, external edits). The button is named by verb + count, and Cancel is the default.
13. A revert is recorded as its own feed event and can itself be undone.
14. Items whose snapshots are gone show a disabled Undo with the reason in its tooltip. They are never hidden.
15. Scopes (All / Needs Attention / Sessions / Settings / Crashes) are a segmented control bound to ⌘1–⌘5.
    Search is `.searchable` with tokens and focuses on ⌘F.
16. Empty states use `ContentUnavailableView` with one sentence and at most one action.
17. Notifications (system banners) fire only on **completed, needsYou, failed**, and only when Summon's window is not key.
18. The menu bar badge and the window's attention count come from one shared computed property (unit-tested).
19. The prompt bar opens from a global hotkey as a floating panel. ↵ runs, Esc dismisses and returns focus to the
    previous app, and the menu bar icon reflects "starting" within 100 ms.
20. Stop agent is always reachable in ≤ 1 action from the panel and window (⌘.), and the live row shows it while running.
21. The menu bar panel shows: live row (if any), up to 5 recent events, one status line, and a footer with
    Open Activity, Settings… (⌘,), Quit (⌘Q). No settings toggles in the panel.
22. Use system containers (`NavigationSplitView`, `List`, `Table`, toolbar, `Form`). No custom glass or shadows on content.
    Liquid Glass applies only through system chrome and is gated by `#available(macOS 26, *)`.
23. Every state color passes WCAG 3:1 against the row background in light and dark mode, and VoiceOver reads
    "Kind, title, time, state" for each row.
24. Permission mode (especially Bypass) appears as a persistent chip in the window and panel status line.

---

## Three original layout ideas for Summon

### Idea A: "Control Tower" (sidebar + feed + inspector)

Three columns. The sidebar holds scopes and projects. The middle is a day-grouped feed with sessions as
disclosure groups. The inspector shows detail and recovery. Status lives in the toolbar.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   Summon                    [● Running 04:12] [Safety net ✓] [⌕ Search  ] │
│         Idle · 1 needs you                                      [▶ Run Agent ⌘N] │
├───────────────┬──────────────────────────────────────┬───────────────────────────┤
│ ACTIVITY      │ ┌ LIVE ─────────────────────────────┐ │ Session “Fix flaky tests” │
│ ◉ All         │ │ ◌ Fix flaky tests      04:12  [■] │ │ macos-plugins · running   │
│ ✋ Needs you 1 │ │   Editing Tests/NetTests.swift…   │ │                           │
│ ◎ Sessions    │ └───────────────────────────────────┘ │ Checkpoints               │
│ ⚙ Settings    │ TODAY                                 │  ⚑ 11:58 “add retry”  ↺   │
│ ✕ Crashes     │ ▾ ✓ Refactor parser     11:20  9 files│  ⚑ 11:49 “split file” ↺   │
│               │     ⚑ Checkpoint “split file”   11:49 │                           │
│ PROJECTS      │     ⚑ Checkpoint “add retry”    11:58 │ Changed files        +/-  │
│ ▣ macos-plug… │   ⚙ Turned off auto-compact     10:02 │  Parser.swift      +40 -12│
│ ▣ dotfiles    │ YESTERDAY                             │  Lexer.swift        +8  -3│
│               │ ▸ ✕ Session crashed     18:31         │                           │
│               │ ▸ ✓ Update README       16:05 2 files │ Not covered: 1 Bash change│
│               │                                       │ [Show Diff] [Restore… ⌘⌫] │
├───────────────┴──────────────────────────────────────┴───────────────────────────┤
│ ↵ Open   ⌘Z Undo last   ⌘K Actions                       42 checkpoints · 2 proj │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Idea B: "Two Lanes" (now lane + history lane, single column, compact)

A single-column window, around 460 pt wide. The top lane is *Now*: things that need a decision or are running. The
bottom lane is *History*. Status is a single sentence, not tiles. It works as a small persistent window next to the editor.

```
┌──────────────────────────────────────────────┐
│ Summon                         ⌕   ⋯   ▶ Run │
│ Agent running · Safety net on · Bypass off   │
├──────────────────────────────────────────────┤
│ NOW                                          │
│  ✋ Approve “rm -rf build/”?   [Deny][Allow]  │
│     Fix flaky tests · macos-plugins · 12s    │
│  ◌ Fix flaky tests                    04:12  │
│     Running swift test…               [■ ⌘.] │
├──────────────────────────────────────────────┤
│ [All] [Sessions] [Settings] [Crashes]        │
│ TODAY                                        │
│  ✓ Refactor parser       9 files      11:20 ›│
│  ⚙ Auto-compact off      via CLI      10:02 ↺│
│  ⚑ Checkpoint “add retry”             09:58 ›│
│ YESTERDAY                                    │
│  ✕ Session crashed       exit 137     18:31 ›│
│  ↺ Reverted “try cache”  3 files      17:10 ›│
├──────────────────────────────────────────────┤
│  Undone: Auto-compact back on   [Redo] ▰▰▰▱▱ │  ← transient toast
└──────────────────────────────────────────────┘
```

### Idea C: "Session Film Strip" (horizontal session timeline + detail)

Sessions are the primary object. The top band is a horizontal, scrollable strip of session "frames"
for today (width ∝ duration, symbol = outcome). Selecting a frame shows its vertical step log below with
checkpoints as rewind points. Settings changes appear as small ticks between frames. Recovery becomes
"scrub back to here".

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Summon   Today ▾                 Safety net ✓ · 42 kept   ⌕   ▶ Run ⌘N   │
├──────────────────────────────────────────────────────────────────────────┤
│ 09:00        10:00 ⚙        11:00               12:00           now      │
│ ├────────────┼─────┼────────┼───────────────────┼───────────────┤        │
│   [✓ README ]      ╎   [✓ Refactor parser────]    [◌ Fix tests……▶]       │
│                    ╎ auto-compact off              ▲ selected            │
├──────────────────────────────────────────────────────────────────────────┤
│ ◌ Fix flaky tests · macos-plugins · running 04:12          [Open] [■ ⌘.] │
│                                                                          │
│  11:58  ⚑ Checkpoint  “add retry to NetClient”            ↺ Rewind here  │
│  12:01  ✎ Edited      Sources/NetClient.swift   +22 −4                   │
│  12:02  ⌘ Ran         swift test (Bash, not undoable)                    │
│  12:04  ◌ Editing     Tests/NetTests.swift…                              │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│ ↵ Open in Claude   ⌘Z Undo last   ⌘⌫ Rewind…   ⌘K Actions                 │
└──────────────────────────────────────────────────────────────────────────┘
```

### Menu bar panel (works with any of the above)

```
┌────────────────────────────────────┐
│ ◌ Fix flaky tests          04:12 ■ │
│   Editing NetTests.swift…          │
│ ✋ Needs approval · Open…           │
├────────────────────────────────────┤
│ ✓ Refactor parser   9 files  11:20 │
│ ⚙ Auto-compact off   CLI     10:02 │
│ ✕ Session crashed    yest.   18:31 │
├────────────────────────────────────┤
│ ⌕ Ask the agent…               ⌘N  │
├────────────────────────────────────┤
│ Safety net on · Bypass off         │
│ Open Activity ⌘0   Settings… ⌘,  Q │
└────────────────────────────────────┘
```

---

## Sources

- Console: https://www.intego.com/mac-security-blog/how-to-use-the-console-app-for-troubleshooting · https://support.apple.com/guide/console/cnsl35710
- Xcode report navigator: https://help.apple.com/xcode/mac/current/en.lproj/dev21d56ecd4.html
- Versions: https://macmost.com/accessing-document-history-on-your-mac.html · https://help.apple.com/pages/mac/5.6/en.lproj/tan7f1de6ec5.html
- Claude Code checkpointing: https://code.claude.com/docs/en/checkpointing
- Claude Code desktop redesign: https://pasqualepillitteri.it/en/news/866/claude-code-desktop-redesign-parallel-sessions
- Proxyman: https://proxyman.com/posts/2019-06-14-getting-started-with-proxyman
- Linear: https://linear.app/docs/inbox · https://linear.app/developers/aig.md · https://linear.app/developers/agent-interaction
- Things: https://blakecrosley.com/es/guides/design/things
- Raycast: https://manual.raycast.com/action-panel · https://blakecrosley.com/fr/guides/design/raycast
- Superhuman: https://blakecrosley.com/guides/design/superhuman · https://blog.superhuman.com/how-to-build-a-remarkable-command-palette/
- Tower: https://www.git-tower.com/features/undo
- GitHub Desktop: https://docs.github.com/en/enterprise-cloud@latest/desktop/managing-commits/undoing-a-commit-in-github-desktop
- Warp: https://docs.warp.dev/agents/capabilities/agent-notifications/
- Cursor: https://tutorials.technology/tutorials/cursor-ai-v3-complete-guide-2026.html · https://forum.cursor.com/t/color-the-agent-chat-background-by-status-running-needs-input-done/168083 · https://forum.cursor.com/t/dock-menu-bar-badge-count-does-not-match-agents-sidebar-needs-attention-glass/168982
- Codex: https://learn.chatgpt.com/docs/app · https://codex.danielvaughan.com/2026/04/08/codex-desktop-automations/
- Conductor: https://www.conductor.build/llms-full.txt
- ChatGPT companion: https://alternativeto.net/news/2024/8/openai-introduces-handy-companion-window-for-chatgpt-on-macos · https://macrumors.com/how-to/use-chatgpt-app-for-macos-mac
- Undo vs confirm: https://www.saasui.design/blog/saas-destructive-actions-confirmation-ux-patterns
- Tahoe / macOS 27 chrome: https://bzamayo.com/tahoe-toolbars · https://mjtsai.com/blog/2026/06/09/golden-gate-sidebars-and-toolbars/
- Relative dates: https://developer.apple.com/documentation/foundation/date/relativeformatstyle.md
