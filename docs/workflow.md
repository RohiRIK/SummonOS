# Plugin lifecycle

How a plugin goes from idea to a public release. Each step names the skill or script that owns the
details; this page only shows the order. Rules: [`AGENTS.md`](../AGENTS.md).

## 1. Plan

- Write the plan in `tasks/todo.md`: explicit requirements, inferred decisions, phases.
- Pick the app shape (menu bar extra, panel, window): `MacAppArchitecture/AppShapes.md`.
- Porting a Linux/Omarchy widget: `PortOmarchyPlugin` (mappings in `Mapping.md`).

## 2. Scaffold

- New repo pair: private `<name>-dev` (all history, PRs) and public `<name>` (snapshots only).
- Clone the dev repo into `plugins/<name>/`, kebab-case, bundle id `local.macplugins.<name>`.
- Package layout, `Info.plist`, scripts: `MacAppBuild/Scaffold.md`. Three targets: `<App>Core`
  (logic, tested), `<App>UI` (views, previews), `<App>` (`@main` only).
- Add `PROJECT-CONTEXT.md` at the repo root (sections in [`AGENTS.md`](../AGENTS.md#project-memory-per-plugin-from-glaze)).

## 3. Build

- Core logic test-first with swift-testing.
- Views through `MacUX` › `DesignPass`. App settings go in a Settings window, never in the panel.
- Work on a branch, never `main`. Conventional commits; push after every commit.

## 4. Verify

From the plugin folder (`MacAppBuild/Verify.md`):

```bash
scripts/check.sh                                         # gate: tests + release bundle + plist lint
../../tools/render-previews.sh . <App>UI                 # any view change; read every PNG
scripts/bundle.sh && open build/<App>.app                # new flows, permissions, system calls
```

Write the manual checklist (permission prompts, admin prompts) unticked into the PR.

## 5. Pull request

```bash
gh pr create ...
scripts/pr-report.sh          # posts the gate report and preview images as a PR comment
```

## 6. Publish and release

After the PR merges into the dev repo's `main`, from this workspace:

```bash
tools/publish-public.sh plugins/<name> main "<message>"     # clean snapshot to the public repo
tools/release.sh plugins/<name> "what's new"                # zip on the public repo's Releases
```

Bump `CFBundleShortVersionString` and `CFBundleVersion` first (`MacAppBuild/Release.md`).

## 7. Record

- Update the plugin's `PROJECT-CONTEXT.md` (Recent History, newest first).
- New plugin or new status: update [`plugins.md`](../plugins.md).
- Lessons go in the skill that owns them ([`AGENTS.md`](../AGENTS.md#record-learnings-on-the-fly));
  user corrections go in `tasks/lessons.md`.
