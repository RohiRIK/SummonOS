#!/usr/bin/env bash
# Render every #Preview in a plugin's UI target through Xcode MCP and copy the PNGs
# to plugins/<name>/docs/previews/ (tracked, so PR comments and the README can embed them).
# and a library scheme for the UI target (previews do not run in executable targets).
#
#   tools/render-previews.sh <plugin-dir> <UI target> [file.swift ...]
set -euo pipefail
readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PLUGIN="$(cd "$1" && pwd -P)"; shift  # physical path: Xcode reports ~/Library/CloudStorage, not the ~/Google Drive symlink
readonly TARGET="$1"; shift
readonly MCP=(bun "$ROOT/tools/xcode-mcp.ts")
readonly OUT="$PLUGIN/docs/previews"

ws="$("${MCP[@]}" XcodeListWorkspaces '{}' | grep -E "workspacePath: $PLUGIN$" | grep -Eo '(workspace|windowtab)-[A-Za-z0-9]+' | head -1)"
[[ -n "$ws" ]] || { echo "Open the package in Xcode first: xed '$PLUGIN'" >&2; exit 1; }
"${MCP[@]}" XcodeSwitchScheme "{\"workspaceIdentifier\":\"$ws\",\"schemeName\":\"$TARGET\"}" >/dev/null

mkdir -p "$OUT"
files=("$@")
# Full run: start clean so deleted previews disappear. Subset run: keep the other renders.
if (( ! ${#files[@]} )); then
  rm -f "$OUT"/*.png
  files=($(cd "$PLUGIN/Sources/$TARGET" && grep -l "#Preview" *.swift))
fi
status=0
for f in "${files[@]}"; do
  count="$(grep -c '#Preview' "$PLUGIN/Sources/$TARGET/$f")"
  for ((i = 0; i < count; i++)); do
    args="$(jq -nc --arg w "$ws" --arg f "$(basename "$PLUGIN")/Sources/$TARGET/$f" --argjson i "$i" \
      '{workspaceIdentifier:$w, sourceFilePath:$f, previewDefinitionIndexInFile:$i, timeout:240}')"
    out="$("${MCP[@]}" RenderPreview "$args" || true)"
    # ponytail: one retry; a render can fail while Xcode is still compiling the previous one.
    grep -q previewSnapshotPath <<<"$out" || out="$("${MCP[@]}" RenderPreview "$args" || true)"
    snap="$(jq -r '.previewSnapshotPath // empty' <<<"$out" 2>/dev/null || true)"
    if [[ -n "$snap" && -f "$snap" ]]; then
      name="$(jq -r '.displayName' <<<"$out" | tr ' /' '__')"
      cp "$snap" "$OUT/${f%.swift}-$i-$name.png"
      echo "ok   $f #$i -> $OUT/${f%.swift}-$i-$name.png"
    else
      status=1
      echo "FAIL $f #$i: $(head -c 300 <<<"$out")"
    fi
  done
done
exit "$status"
