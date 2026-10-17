# Plan: `mac-calendar` — menu bar calendar (new plugin)

Status: PR https://github.com/RohiRIK/mac-calendar-dev/pull/1 (2026-09-29). Previews + manual checks pending. Branch `feat/calendar-panel` in `plugins/mac-calendar`.

## Requirements (explicit)
- Menu bar item; click it and a calendar appears. Simple and efficient.

## Decisions (inferred, cheap to change)
- Menu bar label = today's date as text ("Tue 29"), updates at midnight (`NSCalendarDayChanged`).
- Panel (`.window` style, system-menu look): month title, ‹ Today › buttons, weekday row, 6×7 day grid.
  Today = accent circle; other-month days dimmed. Week start + names from system locale.
- Keys: ← / → month, T = today.
- Footer: Open Calendar (Calendar.app), Open at Login toggle, Quit (⌘Q).
- Dropped: events (EventKit permission + more UI), Settings window, onboarding. Add if asked.

## Phases
- [x] 2 Scaffold: SwiftPM `MacCalendar` / `MacCalendarUI` / `MacCalendarCore`, scripts from mac-network
- [x] 3 Core test-first: `MonthGrid.days(for:calendar:today:)` → 42 cells; tests for Sunday/Monday start, leap Feb, today flag
- [~] 4 UI: panel done; previews blocked on Xcode MCP approval
- [x] 5 Shell: menu bar label, midnight refresh, Quit, Open at Login
- [x] 6 Audit + 7 `check.sh`, launch app, private `mac-calendar-dev` repo, PR + report
- [x] 8 Record: PROJECT-CONTEXT.md, plugins.md, lessons
