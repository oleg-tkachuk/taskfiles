#!/usr/bin/env bash
# Guard: the tag is SemVer
set -euo pipefail
tag="$TAG"
case "$tag" in
  v[0-9]*.[0-9]*.[0-9]*) echo "✔ $tag is SemVer-shaped" ;;
  *) echo "✖ $tag is not vMAJOR.MINOR.PATCH" >&2; exit 1 ;;
esac
