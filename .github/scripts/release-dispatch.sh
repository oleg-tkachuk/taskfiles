#!/usr/bin/env bash
# Dispatch the release
set -euo pipefail
# --input rather than -f: client_payload is nested and the form
# syntax cannot express that. Both values come from Actions itself,
# never from a contributor, and arrive through env rather than an
# Actions expression inside the script, so nothing here is
# substituted into the shell before it runs.
gh api "repos/${GITHUB_REPOSITORY}/dispatches" --input - <<JSON
{
  "event_type": "release",
  "client_payload": {
    "sha": "${GITHUB_SHA}",
    "ci_run_id": "${GITHUB_RUN_ID}"
  }
}
JSON
printf '%s\n' "dispatched release for ${GITHUB_SHA}"
