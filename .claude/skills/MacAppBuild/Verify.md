# Verify: done means proven

A green build proves the code compiles, not that the feature works. Every change ends with this loop.
Adapted from Glaze's validation rules (one required gate, bounded inspection, honest reporting).

## 1. Gate (always)

```bash
scripts/check.sh      # tests + release bundle + Info.plist lint; non-zero on any failure
```

Do not replace it with narrower checks. Fix failures; never skip, suppress, or delete tests.

## 2. Previews (any view change)

```bash
tools/render-previews.sh plugins/<name> <App>UI          # from the workspace root
```

Read every PNG. Check against `MacUX/Review.md` and `MacUX/MenuPanel.md`. Budget: at most 3
render → fix cycles per change; after that, stop and report what is still uncertain.
Previews show content only, not the real window frame, vibrancy, or menu bar placement.

## 3. Run the real app (new flows, permissions, system calls)

```bash
pkill -f "<App>.app/Contents/MacOS/<App>"; scripts/bundle.sh && open build/<App>.app
/usr/bin/log show --last 5m --predicate 'subsystem == "local.macplugins.<name>"' --info --debug
```

Confirm it launched (`pgrep -fl`) and the logs show the expected path. Screenshots need Screen
Recording permission; background sessions do not have it, so ask the user.

## 4. Manual checklist (what only a human can click)

List the exact steps for the user: permission prompts, admin prompts, joining networks, native
file dialogs, drag from Finder. Put them unticked in the PR test plan. Never tick them yourself.

## Bug fixes

1. Reproduce or find the evidence (log line, failing test, screenshot) first.
2. Add a regression test in Core when the bug is in logic.
3. Smallest complete fix at the shared root, not the one caller named in the report.
4. Confirm the reported behavior is gone (test, log, or user check). Say which one.

## Before a PR

1. Branch, never `main`. Conventional commits.
2. Steps 1-2 green, previews committed in `docs/previews/`.
3. `gh pr create …` with a test plan (manual items unticked).
4. `scripts/pr-report.sh`: posts the gate report and preview images as a PR comment.

## Report honestly

State what was verified and how, what was not, and what the user must check. Never claim a runtime
behavior you did not observe.
