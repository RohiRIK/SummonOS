# Tools

Scripts in [`tools/`](../tools). Run them from the workspace root. Per-plugin scripts
(`scripts/test.sh`, `bundle.sh`, `check.sh`, `pr-report.sh`) live in each plugin repo and are
described in `MacAppBuild/Scaffold.md`.

## publish-public.sh

Publishes a dev-repo branch to the public repo as one clean commit.

```bash
tools/publish-public.sh plugins/<name> [branch] "<commit message>"
```

- Exports the branch with `git archive` and drops `PROJECT-CONTEXT.md` (agent memory).
- Refuses to publish if any regex in `tools/private-patterns.txt` matches. That file is gitignored
  and must exist.
- Commits with your GitHub noreply address, so the author email never reaches the public history.
- Needs `gh` signed in and the public repo `<login>/<name>` to exist.

## release.sh

Builds a plugin and uploads the `.app` as a zip to the public repo's GitHub Releases.

```bash
tools/release.sh plugins/<name> ["extra release notes"]
```

- Runs only on `main`, and only if `scripts/check.sh` passes.
- Version and tag (`v<version>`) come from `Resources/Info.plist`.
- Zips with `ditto` to keep the signature, and writes install notes for an un-notarized app.

## render-previews.sh

Renders every `#Preview` in a plugin's UI target through Xcode MCP and saves PNGs to
`plugins/<name>/docs/previews/`.

```bash
tools/render-previews.sh plugins/<name> <App>UI [File.swift ...]
```

- Open the package in Xcode first (`xed plugins/<name>`); the first use per folder needs Allow in Xcode.
- With no files, it clears old PNGs and renders all previews. With files, it renders only those.
- Retries a failed render once. Needs `bun` and `jq`.

## xcode-mcp.ts

Calls one Xcode MCP tool without an MCP client, for sessions where the `xcode` server is not loaded.

```bash
bun tools/xcode-mcp.ts list
bun tools/xcode-mcp.ts <ToolName> '<json args>' [--out dir]
```

Text results print to stdout. Image results are saved as PNGs in `--out` (default `./build/previews`).
