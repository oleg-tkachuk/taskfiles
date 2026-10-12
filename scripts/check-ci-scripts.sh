#!/usr/bin/env bash
# Report a workflow step whose script lives in the workflow rather than in
# .github/scripts, and a script that nothing runs or that is not there.
#
# A script inside YAML is linted by nothing, cannot be run locally, and is
# the one place zizmor has to guess at what reaches the shell. One-command
# steps stay inline; anything longer is a file a step calls.
#
# Usage: check-ci-scripts.sh <workflows dir> <scripts dir>   (exit 1 on a finding)
set -euo pipefail

command -v yq >/dev/null || { printf '%s\n' "yq is not installed — https://github.com/mikefarah/yq#install" >&2; exit 2; }

workflows=$1
scripts=$2
found=0

# Every run: of every step as "<file>\t<multi-line?>\t<first line>". yq
# decides what is multi-line; a "\n" inside a printf format is not.
runs=$(for f in "$workflows"/*.yml; do
  yq -r '.jobs[].steps[] | select(has("run")) | .run | sub("\n+$"; "")
         | [(test("\n") | tostring), (split("\n") | .[0])] | @tsv' "$f" \
    | sed "s|^|$f	|"
done)

while IFS=$'\t' read -r file multi first; do
  [ -n "$file" ] || continue
  if [ "$multi" = true ]; then
    printf '%s: a multi-line run: belongs in %s/: %s\n' "$file" "$scripts" "$first"
    found=1
  fi
done <<< "$runs"

# Every script a step runs exists, and every script is run by some step.
for s in "$scripts"/*.sh; do
  [ -e "$s" ] || continue
  case "$s" in *.test.sh) continue ;; esac
  name=${s##*/}
  if ! grep -qF "/$name" <<< "$runs"; then
    printf '%s: no workflow step runs it\n' "$s"
    found=1
  fi
done
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  [ -e "$scripts/$ref" ] || { printf '%s: a step runs %s, which is not there\n' "$workflows" "$ref"; found=1; }
done < <(grep -oE '\.github/scripts/[A-Za-z0-9._-]+\.sh' <<< "$runs" | sed 's|.*/||' | sort -u)

exit "$found"
