#!/usr/bin/env bash
# Notice: a newer Task exists
set -euo pipefail
latest=$(gh release view --repo go-task/task --json tagName --jq '.tagName' | sed 's/^v//')
if [ "$latest" != "$PINNED" ]; then
  echo "::notice::Task $latest is out; this repository pins $PINNED. Bump TASK_VERSION in this file after reading the changelog."
else
  echo "✔ TASK_VERSION $PINNED is the current release"
fi
