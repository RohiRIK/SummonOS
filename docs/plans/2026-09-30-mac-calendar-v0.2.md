# Plan: `mac-calendar` v0.2 — events, reminders, quick add, Hebrew dates, hotkey, week view

Status: done (2026-09-30). Merged mac-calendar-dev PR #2, public snapshot published. Branch `feat/events` in `plugins/mac-calendar`.

## Requirements (explicit, from the user)
1. Show events from the user's calendars (EventKit).
4. Quick add: type "Lunch with Dan Fri 1pm" and it creates the event.
8. Hebrew date under each day + Israeli holidays.
9. Global hotkey ⌥⌘P opens the panel.
10. Reminders due each day.
11. Week view.

## Decisions (inferred, cheap to change)
- Permissions: Calendars + Reminders full access, requested only from a Settings toggle (user action).
  Denied: Settings explains and links to System Settings › Privacy. Info.plist usage strings.
  No sandbox / hardened runtime, so no entitlements needed.
- Panel: day dots (up to 3 calendar colors) under each day. Click a day to select it; the list under
  the grid shows that day's events (time, title, calendar color) and reminders (checkbox completes it).
  Default selection = today. List scrolls past ~6 rows so the panel stays compact.
- Quick add: a text field at the bottom of the day list. `NSDataDetector` (Foundation) finds the date;
  the rest is the title. No time = all-day on the selected day. Duration 1 h (or detector duration).
  Goes to the default calendar for new events. Parser in Core, tested.
- Hebrew: `Calendar(identifier: .hebrew)`, gematria numerals via locale `he@numbers=hebr` (verified:
  "י״ט תשרי ה׳תשפ״ז"). Holidays computed in Core from Hebrew dates (Rosh Hashana, Yom Kippur, Sukkot,
  Simchat Torah, Hanukkah, Tu BiShvat, Purim, Pesach, Yom HaShoah, Yom HaZikaron, Yom HaAtzmaut,
  Lag BaOmer, Yom Yerushalayim, Shavuot, Tisha B'Av), with Israeli postponement rules. Tested against
  known dates. Offline, no permission. Two toggles in Settings, both OFF by default (user: optional).
  User chose: Hebrew letters, built-in holidays, agenda-list week view.
- Hotkey ⌥⌘P: Carbon `RegisterEventHotKey` (no Accessibility permission). Opens the existing
  MenuBarExtra panel by clicking its `NSStatusBarButton` (public AppKit type), so the app shape stays
  as is. Toggle in Settings (on by default). Fixed shortcut, not rebindable.
- Week view: Month/Week switch in the panel header (a view mode, not a setting; remembered).
  Week = 7 rows (day name + date + Hebrew date) with that day's events under each; ‹ › moves by week.
- Live updates: `EKEventStoreChanged` notification, no polling.

## Phases
- [x] 1 Core, test-first: `HebrewDates` (day label, holidays + rules), `QuickAddParser`, week range
- [x] 2 `EventService` (EventKit wrapper: access, events + reminders for a range, create event, complete reminder)
- [x] 3 Panel: dots, day selection, day list, quick add, reminders, Hebrew row, holidays
- [x] 4 Week view + header switch
- [x] 5 Hotkey ⌥⌘P
- [x] 6 Settings: Calendars (events toggle, calendar picker), Reminders, Hebrew, Shortcut sections
- [x] 7 Verify: 29 tests, window frames logged, user verified in app: check.sh, previews, run app, grant permissions, manual checklist
- [x] 8 PR, merge, publish public, PROJECT-CONTEXT, lessons

## Review
- Shipped all six. Surprises: MenuBarExtra shrinks its window late and toward the bottom (fixed with FitWindowHeight); ad-hoc re-signing drops TCC grants (designated requirement); NSDataDetector reads "10:30" as the next 10:30.
