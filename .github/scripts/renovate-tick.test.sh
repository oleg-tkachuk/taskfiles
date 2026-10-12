#!/usr/bin/env bash
# Cases for renovate-tick.sh: which dashboard edits start a Renovate pass.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# expect <true|false> <name> <body before> <body after>
expect() {
  want=$1 name=$2
  : > "$work/out"
  BODY_BEFORE=$3 BODY_AFTER=$4 GITHUB_OUTPUT="$work/out" bash "$here/renovate-tick.sh" >/dev/null
  got=$(sed -n 's/^proceed=//p' "$work/out")
  if [ "$got" = "$want" ]; then
    printf '%s\n' "✔ $name: proceed=$got"
  else
    printf '%s\n' "✖ $name: want proceed=$want, got $got" >&2
    failures=$((failures + 1))
  fi
}

a_open=' - [ ] <!-- approve-branch=renovate/a -->chore(deps): update a'
a_done=' - [x] <!-- approve-branch=renovate/a -->chore(deps): update a'
b_open=' - [ ] <!-- approve-branch=renovate/b -->chore(deps): update b'
b_done=' - [x] <!-- approve-branch=renovate/b -->chore(deps): update b'
all_done='- [x] <!-- create-all-awaiting-schedule-prs -->Create all awaiting schedule PRs at once'

expect true  a-box-ticked            "$a_open"$'\n'"$b_open" "$a_open"$'\n'"$b_done"
expect true  top-level-box-ticked    "${all_done/\[x\]/[ ]}"  "$all_done"
expect true  ticked-and-reordered    "$a_open"$'\n'"$b_open" "$b_done"$'\n'"$a_open"
expect false renovate-unticks        "$a_done"$'\n'"$b_open" "$a_open"$'\n'"$b_open"
expect false renovate-reorders       "$a_done"$'\n'"$b_open" "$b_open"$'\n'"$a_done"
expect false no-change               "$a_open" "$a_open"
expect false box-without-marker      '- [ ] a note' '- [x] a note'
expect false empty-before-and-after  '' ''
expect false ticked-box-removed      "$a_done" ''

[ "$failures" = 0 ]
