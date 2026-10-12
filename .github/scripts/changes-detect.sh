#!/usr/bin/env bash
# Decide: does this change touch anything outside docs and workflows
set -euo pipefail
if [ -z "${BASE:-}" ] || ! git cat-file -e "$BASE" 2>/dev/null; then
  echo "smoke_skippable=false" >> "$GITHUB_OUTPUT"
  echo "no usable base for $EVENT — running the full matrix"
  exit 0
fi

changed=$(git diff --name-only "$BASE" "$HEAD")
# Docs and workflow configuration cannot change what consumer-smoke proves;
# .github/scripts holds the smoke steps themselves, so a change there does.
relevant=$(
  printf '%s\n' "$changed" | grep -E '^\.github/scripts/' \
    || printf '%s\n' "$changed" | grep -vE '(\.md$|^\.github/)' \
    || true
)
if [ -n "$changed" ] && [ -z "$relevant" ]; then
  echo "smoke_skippable=true" >> "$GITHUB_OUTPUT"
else
  echo "smoke_skippable=false" >> "$GITHUB_OUTPUT"
fi
printf 'changed files:\n%s\n' "${changed:-<none>}"
