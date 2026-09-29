# Port Workflow

Port one Omarchy/Linux bar widget to a native macOS app.

## Step 1: Clone and read everything

```bash
git clone --depth 1 <url> "$CLAUDE_JOB_DIR/tmp/<source>"   # scratch copy, not in plugins/
```

Read `manifest.json`, `README.md`, every helper script, and the test files in full.
Read the QML entry point for: `Process { command: ... }` blocks (every shell-out),
key handlers, screens/states, and timers (polling intervals).

## Step 2: Feature inventory

Write a table in `tasks/todo.md`:

| Feature | Source (file:line) | Linux dependency | macOS approach | Keep / drop |

Every row of the source README's feature list and key table must appear.
A feature marked "drop" needs a one-line reason (no macOS API, not wanted).

## Step 3: Map dependencies

For each Linux command or QML import, look it up in `../Mapping.md`.
Missing row: research the macOS API (Apple docs, `man networksetup`, etc.),
verify it on this Mac with a real command, then add the row to `Mapping.md`.

## Step 4: Plan and confirm

Plan phases in `tasks/todo.md`: repo, logic + tests, UI, verify. List risks
(permissions, admin prompts, dropped features). Wait for user approval.

## Step 5: Repo

```bash
mkdir -p plugins/<name> && cd plugins/<name> && git init
```

Scaffold per the `MacAppBuild` skill. Then:

```bash
gh repo create <name> --private --source . --push
```

Add the plugin to `plugins.md`.

## Step 6: Logic first, test-first

- Port pure helpers (`Model.js`) to `Sources/<App>Core/Model.swift`. Port their test cases first, as swift-testing `@Test`s.
- Port system helpers (`settings.py`) to a Swift type that runs commands through an injected runner, so tests use a fake binary or closure. Keep every validation branch and every error message.
- `scripts/test.sh` green before any view code.

## Step 7: UI

Load `MacUX`. Rebuild each screen from the inventory. Keep the source key bindings.

## Step 8: Verify

- `scripts/test.sh`, `scripts/bundle.sh`, launch the `.app`, click through every inventory row.
- README: features, what was dropped and why, install, uninstall, permissions asked.
- Record new gotchas (see AGENTS.md "Record learnings on the fly").
