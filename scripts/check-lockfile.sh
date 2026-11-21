#!/usr/bin/env bash
# Report every package.json its package-lock.json does not satisfy.
#
# `npm ci` refuses to install from a lock file that has fallen behind its
# package.json. The root one is installed by release.yml alone, after a merge:
# a bump that moves package.json and leaves the lock where it was passes every
# check on its pull request and then stops every release.
#
# npm is asked, not imitated: this is `npm ci` itself, told to install
# nothing. A lock that satisfies its package.json is passed from the two files
# alone. One that does not fails either way; to name what is behind or missing
# npm reads the registry, and with none in reach its own error is shown.
#
# Usage: check-lockfile.sh <directory>...   (exit 1 when anything is reported)
set -euo pipefail

command -v npm >/dev/null || { printf '%s\n' "npm is not installed — https://nodejs.org/en/download" >&2; exit 2; }

MANIFEST=package.json
LOCK=package-lock.json

log=$(mktemp)
trap 'rm -f "$log"' EXIT

found=0
for dir in "$@"; do
  for name in "$MANIFEST" "$LOCK"; do
    [ -f "$dir/$name" ] || { printf '%s\n' "$dir: no $name"; found=1; continue 2; }
  done
  # No install scripts, as everywhere npm ci runs here; none would run under
  # --dry-run, and the flag keeps that from resting on it.
  if (cd "$dir" && npm ci --ignore-scripts --dry-run) > "$log" 2>&1; then continue; fi
  found=1
  printf '%s\n' "$dir: $LOCK does not satisfy $MANIFEST — run npm install there, and commit the lock file"
  # What npm named, where it named anything; else all it said.
  awk '
    { all[NR] = $0 }
    sub(/^npm error (Invalid|Missing): /, "") { print "    " $0; named++ }
    END { if (!named) for (i = 1; i <= NR; i++) print "    " all[i] }' "$log"
done

exit "$found"
