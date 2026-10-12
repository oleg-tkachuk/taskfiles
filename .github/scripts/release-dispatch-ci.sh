#!/usr/bin/env bash
# Release the tag it just pushed
set -euo pipefail

# Read from git rather than parsing semantic-release's prose:
# it tags the commit that was checked out, so no new tag here means
# no release was due and there is nothing to publish.
tag="$(git tag --points-at HEAD | head -1)"

if [ -z "$tag" ]; then
  printf '%s\n' "no new tag on this commit — no release was due"
  exit 0
fi

printf '%s\n' "dispatching ci.yml to verify and publish $tag"
gh workflow run ci.yml -f tag="$tag"
