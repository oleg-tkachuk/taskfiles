#!/usr/bin/env bash
# Report a Renovate setup that has broken without saying so.
#
# Every failure here is silent in Renovate itself: a pin its regex no longer
# matches gets no pull request, for ever; a post-upgrade command missing from
# the allow-list is skipped with a log warning; a root renovate.json shadows
# .github/renovate.json entirely. None of them turns anything red.
#
# Usage: check-renovate.sh [repository root]   (exit 1 on a finding)
set -euo pipefail

command -v yq >/dev/null || { printf '%s\n' "yq is not installed — https://github.com/mikefarah/yq#install" >&2; exit 2; }

root=${1:-.}
cd "$root"

CONFIG=.github/renovate.json
WORKFLOW=.github/workflows/renovate.yml
RELEASE_NOTES=.github/release.yml
# Renovate reads the root file before .github/, and a stale one wins.
SHADOW=renovate.json
ANNOTATION='# renovate:'
# The job-level condition that keeps an issue event from anyone but the
# dashboard's real author from starting a run holding the token.
AUTHOR_CHECK='github.event.issue.user.login == github.repository_owner'
# A pin no built-in manager sees: a *_VERSION key, or a `uvx tool@x`.
PIN_RE='^[[:space:]]*[A-Z0-9_]+_VERSION:[[:space:]]*[0-9]|uvx [^[:space:]]+@'

found=0
report() { printf '%s\n' "$*"; found=1; }

[ -e "$SHADOW" ] && report "$SHADOW: shadows $CONFIG — Renovate reads it first and ignores the other"

json() { yq -p json -o tsv "$1" "$CONFIG"; }

# ─── every annotated pin is matched, and every pin is annotated ─────────────
# One per line; no mapfile, which macOS's bash 3.2 does not have.
patterns=$(json '.customManagers[].managerFilePatterns[] | sub("^/"; "") | sub("/$"; "")')
regexes=$(json '.customManagers[].matchStrings[]')

for file in $(git ls-files 2>/dev/null || find . -type f | sed 's|^\./||'); do
  managed=false
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if FILE=$file RE=$p perl -e 'exit($ENV{FILE} =~ /$ENV{RE}/ ? 0 : 1)'; then managed=true; break; fi
  done <<< "$patterns"
  [ "$managed" = true ] || continue

  annotated=$(grep -c "$ANNOTATION" "$file" || true)
  matched=0
  while IFS= read -r re; do
    [ -n "$re" ] || continue
    n=$(RE=$re perl -0777 -ne 'my $n = 0; $n++ while /$ENV{RE}/g; print $n' "$file")
    matched=$((matched + n))
  done <<< "$regexes"
  [ "$matched" = "$annotated" ] || report "$file: $annotated annotated pin(s), $matched matched by $CONFIG's customManagers"

  bare=$(PIN_RE=$PIN_RE ANN=$ANNOTATION F=$file awk '
    $0 ~ ENVIRON["PIN_RE"] && index(prev, ENVIRON["ANN"]) == 0 { printf "%s:%d: a pin with no `%s` comment above it\n", ENVIRON["F"], NR, ENVIRON["ANN"] }
    { prev = $0 }' "$file")
  [ -z "$bare" ] || report "$bare"
done

# ─── every post-upgrade command is allowed ──────────────────────────────────
allowed=$(yq '.jobs[].steps[] | select(.uses // "" | test("^renovatebot/github-action@")) | .env.RENOVATE_ALLOWED_COMMANDS // "[]"' "$WORKFLOW")
allow=$(printf '%s' "$allowed" | yq -p json -o tsv '.[]')
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  ok=false
  while IFS= read -r re; do
    [ -n "$re" ] || continue
    if CMD=$cmd RE=$re perl -e 'exit($ENV{CMD} =~ /$ENV{RE}/ ? 0 : 1)'; then ok=true; break; fi
  done <<< "$allow"
  [ "$ok" = true ] || report "$CONFIG: postUpgradeTasks command '$cmd' matches nothing in $WORKFLOW's RENOVATE_ALLOWED_COMMANDS"
done < <(json '.. | select(tag == "!!map" and has("postUpgradeTasks")) | .postUpgradeTasks.commands[]')

# ─── an issue event still has to come from the dashboard's author ───────────
yq '.jobs[].if // ""' "$WORKFLOW" | grep -qF "$AUTHOR_CHECK" \
  || report "$WORKFLOW: no job checks '$AUTHOR_CHECK' — any issue titled Dependency Dashboard could start a run"

# ─── Renovate's labels keep its pull requests out of the release notes ──────
excluded=$(yq '.changelog.exclude.labels[]' "$RELEASE_NOTES")
while IFS= read -r label; do
  [ -n "$label" ] || continue
  grep -qxF "$label" <<< "$excluded" || report "$RELEASE_NOTES: label '$label' from $CONFIG is not excluded from the release notes"
done < <(json '.labels[]')

exit "$found"
