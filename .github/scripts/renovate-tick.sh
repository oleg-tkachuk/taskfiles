#!/usr/bin/env bash
# Decide: a Dependency Dashboard checkbox was newly ticked
#
# Renovate rewrites the dashboard on every pass with a personal access token,
# and a PAT's edit starts workflows, so `issues: edited` alone would run
# Renovate for ever. The actor cannot tell the two apart — the PAT acts as its
# owner — so this compares WHAT changed: proceed only when a checkbox carrying
# a Renovate marker went from unchecked to checked. Renovate un-ticks after
# acting, so its own rewrite never adds one.
#
# Input: BODY_BEFORE, BODY_AFTER (the issue body before and after the edit).
# Output: proceed=true|false appended to $GITHUB_OUTPUT.
set -euo pipefail

# A ticked task-list item. Renovate indents nested ones.
TICKED_RE='^ *- \[x\]'
# Renovate tags each actionable checkbox with an HTML comment; a stray
# checkbox in prose has none.
MARKER_RE='<!--'

# Through ENVIRON rather than -v, which would eat the backslashes.
# Sorted, so the comparison is by content and not by position: Renovate
# reorders the list as updates come and go.
ticked() {
  printf '%s\n' "$1" | TICKED_RE=$TICKED_RE MARKER_RE=$MARKER_RE awk '$0 ~ ENVIRON["TICKED_RE"] && $0 ~ ENVIRON["MARKER_RE"]' | sort
}

added=$(comm -13 <(ticked "${BODY_BEFORE:-}") <(ticked "${BODY_AFTER:-}") | awk 'NF')

if [ -z "$added" ]; then
  echo "no Renovate checkbox was newly ticked — nothing to do"
  echo "proceed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "newly ticked:"
printf '%s\n' "$added"
echo "proceed=true" >> "$GITHUB_OUTPUT"
