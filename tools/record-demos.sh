#!/usr/bin/env bash
# Re-record the macctl README demos on a real Mac, replacing the illustrative transcripts.
#
#   tools/record-demos.sh            # transcripts + SVG cards + demo.gif (if vhs is installed)
#   tools/record-demos.sh --no-gif   # transcripts + SVG cards only
#
# For each macctl/docs/demo/*.txt it runs every `$ macctl ...` line from macctl/ in a pseudo-terminal
# (so output is the human form, not JSON), saves stdout, replaces $HOME with /Users/you and every regex in
# tools/private-patterns.txt (if present, one per line) with <private>, then runs tools/readme-art.py
# and `vhs macctl/docs/demo/demo.tape`. Read-only: it refuses any command that could write
# (set/apply/undo without --dry-run). Needs macctl on PATH (see macctl/README.md, Install).
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DEMO="$ROOT/macctl/docs/demo"
readonly PATTERNS="$ROOT/tools/private-patterns.txt"
readonly WORK="$(mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT

die() { echo "record-demos: $*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || die "run this on a Mac (macctl reads real macOS settings)"
command -v macctl >/dev/null || die "macctl is not on PATH; build and install it first (macctl/README.md)"
command -v python3 >/dev/null || die "python3 is required (Xcode Command Line Tools ship one)"

# Only these subcommands may run; set/apply/undo only with --dry-run.
is_read_only() {
  local cmd="$1"
  [[ "$cmd" == macctl\ * ]] || return 1
  [[ "$cmd" != *[\;\|\&\$\`\<\>\(\)]* ]] || return 1   # one plain command, no shell tricks
  case "$(awk '{print $2}' <<<"$cmd")" in
    doctor|list|describe|get|diff|snapshot) return 0 ;;
    set|apply) [[ " $cmd " == *" --dry-run "* ]] ;;
    *) return 1 ;;
  esac
}

# sed script for vhs (the GIF cannot be redacted afterwards, so the tape filters live output).
: > "$WORK/redact.sed"
if [[ -f "$PATTERNS" ]]; then
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    printf 's\001%s\001<private>\001g\n' "$pattern" >> "$WORK/redact.sed"
  done < "$PATTERNS"
else
  echo "record-demos: no tools/private-patterns.txt; only \$HOME is redacted" >&2
fi

redact() {
  python3 - "$PATTERNS" "$HOME" <<'PY'
import re, sys
patterns, home = sys.argv[1], sys.argv[2]
text = sys.stdin.read().replace("\r", "").replace("^D\b\b", "")  # `script` artifacts
text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text).replace(home, "/Users/you")
try:
    lines = open(patterns).read().splitlines()
except FileNotFoundError:
    lines = []
for p in lines:
    if p.strip() and not p.startswith("#"):
        text = re.sub(p, "<private>", text)
sys.stdout.write(text.rstrip("\n") + "\n")
PY
}

readonly MACOS="$(sw_vers -productVersion)"
readonly SHA="$(git -C "$ROOT" rev-parse --short HEAD)"

for file in "$DEMO"/*.txt; do
  out="$WORK/$(basename "$file")"
  echo "# recorded on macOS $MACOS with macctl at $SHA by tools/record-demos.sh" > "$out"
  while IFS= read -r line; do
    [[ "$line" == '$ '* ]] || continue
    cmd="${line#\$ }"
    is_read_only "$cmd" || die "$(basename "$file"): refusing a command that could write: $cmd"
    echo "\$ $cmd" >> "$out"
    # `script` gives macctl a terminal so it prints the human form; a nonzero exit is still a valid demo.
    (cd "$ROOT/macctl" && script -q /dev/null /bin/sh -c "$cmd" < /dev/null || true) | redact >> "$out"
  done < "$file"
  grep -q '^\$ ' "$out" || die "$(basename "$file") has no \$ command lines"
  mv "$out" "$file"
  echo "recorded $(basename "$file")"
done

python3 "$ROOT/tools/readme-art.py"

if [[ "${1:-}" == --no-gif ]]; then
  exit 0
fi
if command -v vhs >/dev/null; then
  (cd "$ROOT" && MACCTL_DEMO_SED="$WORK/redact.sed" vhs macctl/docs/demo/demo.tape)
  echo "wrote macctl/docs/demo/demo.gif; watch it once before committing (git add -f if *.gif is ignored)"
else
  echo "vhs not installed (brew install vhs); skipped demo.gif" >&2
fi

echo "Review: git diff macctl/docs/demo docs/assets/demo"
