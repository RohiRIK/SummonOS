#!/usr/bin/env bash
# Refuse publication on a match OR an incomplete scan. Never print matching content.
set -euo pipefail
export LC_ALL=C
patterns=${1:?usage: private-scan.sh patterns-file exported-directory}
tree=${2:?usage: private-scan.sh patterns-file exported-directory}
[[ -f $patterns && -r $patterns && -s $patterns ]] || {
  echo "Private scan requires a readable, nonempty patterns file." >&2; exit 1;
}
[[ -d $tree && ! -L $tree ]] || { echo "Private scan requires an exported directory." >&2; exit 1; }
tree=$(cd "$tree" && pwd -P)
# Blank expressions match every line and usually indicate an accidental configuration error.
status=0
grep -Eq '^[[:space:]]*$' "$patterns" || status=$?
[[ $status == 1 ]] || { echo "Private patterns must contain only nonblank expressions." >&2; exit 1; }
status=0
grep -aEf "$patterns" /dev/null >/dev/null 2>&1 || status=$?
[[ $status -le 1 ]] || { echo "Private scan failed: invalid patterns." >&2; exit 1; }
manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT
# Capture traversal status directly: process substitution would silently hide a find failure.
find "$tree" -mindepth 1 -print0 >"$manifest" || {
  echo "Refusing publication: could not enumerate the complete export." >&2; exit 1;
}
while IFS= read -r -d '' entry; do
  # Names can disclose private hostnames, addresses, or identities even when the file is empty.
  relative=${entry#"$tree"/}
  status=0
  printf '%s\n' "$relative" | grep -aEf "$patterns" >/dev/null 2>&1 || status=$?
  case $status in
    0) echo "Refusing publication: private data found in an exported path." >&2; exit 1 ;;
    1) ;;
    *) echo "Refusing publication: exported path scanning failed." >&2; exit 1 ;;
  esac
  status=0
  if [[ -L $entry ]]; then
    target=$(readlink "$entry") || { echo "Could not read an exported symlink." >&2; exit 1; }
    printf '%s\n' "$target" | grep -aEf "$patterns" >/dev/null 2>&1 || status=$?
  elif [[ -f $entry ]]; then
    # Read every regular file, including binary assets, without following exported symlinks.
    grep -aEf "$patterns" -- "$entry" >/dev/null 2>&1 || status=$?
  elif [[ -d $entry ]]; then
    continue
  else
    echo "Refusing publication: unsupported or inaccessible exported entry." >&2; exit 1
  fi
  case $status in
    0) echo "Refusing publication: private data found in an exported file or symlink." >&2; exit 1 ;;
    1) ;;
    *) echo "Refusing publication: the privacy scan did not complete." >&2; exit 1 ;;
  esac
done <"$manifest"
