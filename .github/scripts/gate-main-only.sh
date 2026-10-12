#!/usr/bin/env bash
# Guard: releases only from main
set -euo pipefail
if ! git rev-parse --verify --quiet origin/main >/dev/null; then
  git fetch --quiet origin main:refs/remotes/origin/main
fi
if git merge-base --is-ancestor HEAD origin/main; then
  echo "✔ $TAG is a commit on main"
  exit 0
fi
echo "::error::Releases must be cut from main. $TAG points at a commit main does not contain, so it would publish a tree that never passed CI on main — and consumers pinning ?ref=$TAG would fetch exactly that tree."
exit 1
