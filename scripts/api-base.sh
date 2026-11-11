#!/usr/bin/env bash
# Print the release this tree's public API is compared against.
#
# That is the latest release tag HEAD descends from — unless HEAD is that tag.
# A release run checks the tag out, and compared with itself a release has
# shipped everything: every API_REMOVED and API_DEFAULTS_CHANGED entry it
# still carries reads as stale, and the release that needed the entry fails
# its own gate. On a tag, the comparison is with the release before it.
#
# The first release has none before it and is compared with itself.
#
# Usage: api-base.sh   (exit 1 when no release tag is reachable)
set -euo pipefail

# What a release tag looks like, as `git describe --match` takes it.
readonly RELEASE_TAGS='v[0-9]*'

# latest <commit> — the nearest release tag at or before the commit.
latest() { git describe --tags --abbrev=0 --match "$RELEASE_TAGS" "$1" 2>/dev/null; }

base=$(latest HEAD)
if [ "$(git rev-parse "$base^{commit}")" = "$(git rev-parse HEAD)" ]; then
  base=$(latest 'HEAD^') || true
  [ -n "$base" ] || base=$(latest HEAD)
fi
printf '%s\n' "$base"
