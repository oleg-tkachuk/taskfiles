#!/usr/bin/env bash
# Publish: the GitHub release
set -euo pipefail
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "✔ release $TAG already exists"
  exit 0
fi
gh release create "$TAG" --title "$TAG" --generate-notes --verify-tag
echo "✔ released $TAG"
