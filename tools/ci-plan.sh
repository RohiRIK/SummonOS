#!/bin/bash
# What swift.yml builds for a change: tools/ci-plan.sh <event> <changed-files-file> <packages-json>
# Prints GitHub outputs (key=value): matrix (build-and-test include list), core (Summon/macctl for Xcode 27),
# macctl (crash matrix), skills (design skill examples). A PR builds only the packages its files are in; a push to
# main, a manual run, an unknown diff, a workflow change or any file this can't place builds everything.
set -euo pipefail

event=$1 files_file=$2 packages=$3
summon=incubator/summon
all=()
while IFS= read -r p; do all+=("$p"); done < <(jq -r '.[]' <<<"$packages") # no mapfile: macOS bash is 3.2

everything=false
skills=false
selected=()
add() { local p; for p in "${selected[@]+"${selected[@]}"}"; do [ "$p" = "$1" ] && return; done; selected+=("$1"); }

if [ "$event" != pull_request ] || [ ! -s "$files_file" ]; then
  everything=true
else
  while IFS= read -r f || [ -n "$f" ]; do # the last line may have no newline
    [ -n "$f" ] || continue
    # The longest package path that holds the file (a template is inside incubator/summon).
    match=""
    for p in "${all[@]}"; do
      case "$f" in "$p"/*) [ ${#p} -gt ${#match} ] && match=$p ;; esac
    done
    if [ -n "$match" ]; then
      add "$match"
      # Summon's own tests read the templates (ProjectTests), so a template change tests Summon too.
      case "$match" in "$summon"/templates/*) add "$summon" ;; esac
      continue
    fi
    case "$f" in
      docs/*) ;;                                    # docs only: nothing to build
      .claude/*|tools/check-skills.py) skills=true ;; # design skill examples are checked by their own job
      tools/*|install.sh|*.md) ;;                   # the workspace job checks these on every run
      *) everything=true ;;                         # workflows and anything else: build it all
    esac
  done <"$files_file"
fi

if [ "$everything" = true ]; then
  selected=("${all[@]}")
  skills=true
fi

# Summon and macctl on the minimum OS and the current one; templates (small starters) on the current one only.
include=()
core=()
for p in "${selected[@]+"${selected[@]}"}"; do
  case "$p" in
    "$summon"/templates/*) include+=("{\"os\":\"macos-26\",\"package\":\"$p\"}") ;;
    *) include+=("{\"os\":\"macos-26\",\"package\":\"$p\"}" "{\"os\":\"macos-15\",\"package\":\"$p\"}") ;;
  esac
  case "$p" in "$summon"|macctl) core+=("\"$p\"") ;; esac
done

macctl=false
for p in "${selected[@]+"${selected[@]}"}"; do [ "$p" = macctl ] && macctl=true; done

join() { local IFS=,; echo "$*"; }
echo "matrix={\"include\":[$(join "${include[@]+"${include[@]}"}")]}"
echo "core=[$(join "${core[@]+"${core[@]}"}")]"
echo "macctl=$macctl"
echo "skills=$skills"
