#!/usr/bin/env bash
# Report a module var that resolves an input a caller may pass on the task call.
#
# A var in a module's top-level vars block is evaluated in that file's own
# scope: it sees what the consumer set at include time, and nothing a caller
# passes on the call itself. A module var pre-chewing such an input resolves to
# empty while the task it feeds sees the real value. An input a task
# `requires:` is by definition allowed to arrive at call time, so no top-level
# var may read one — not as a template, a sh: command or a ref.
#
# Usage: check-scope.sh <Taskfile>...   (exit 1 when anything is reported)
set -euo pipefail

command -v yq >/dev/null || { printf '%s\n' "yq is not installed — https://github.com/mikefarah/yq#install" >&2; exit 2; }

found=0
for file in "$@"; do
  # Every form requires: takes — a flow list, a block list, {name:, enum:}.
  required=$(yq -r '.tasks // {} | .[] | select(type == "!!map") | .requires.vars // [] | .[] | (.name // .)' "$file" | sort -u)
  [ -n "$required" ] || continue
  # "<var>\t<text>" for each top-level var: its string, sh: or ref:.
  vars=$(yq -r '.vars // {} | to_entries[] | .key + "\t" + ((.value | select(type == "!!str")) // .value.sh // .value.ref // "")' "$file")
  while IFS=$'\t' read -r name text; do
    [ -n "$name" ] || continue
    while IFS= read -r input; do
      [ -n "$input" ] || continue
      if printf '%s' "$text" | grep -qE "(^|[^A-Za-z0-9_])\\.${input}([^A-Za-z0-9_]|\$)"; then
        printf '%s: var %s resolves %s, which a caller may pass on the call\n' "$file" "$name" "$input"
        found=1
      fi
    done <<< "$required"
  done <<< "$vars"
done

exit "$found"
