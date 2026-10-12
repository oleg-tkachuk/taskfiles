#!/usr/bin/env bash
# Guard: RENOVATE_TOKEN is set
#
# Fails with a sentence rather than with Renovate's own authentication error,
# which names neither the secret nor the permissions it needs.
set -euo pipefail

[ -n "${RENOVATE_TOKEN:-}" ] && exit 0

echo "::error::the RENOVATE_TOKEN secret is not set"
cat >&2 <<'EOF'
Renovate needs a token of its own. GITHUB_TOKEN cannot be used: a pull
request opened with it does not trigger `pull_request` workflows, so no
required check would ever report and branch protection would block the merge
for ever.

Create a fine-grained personal access token scoped to this repository with:

  Contents        read and write
  Pull requests   read and write
  Issues          read and write   (the Dependency Dashboard)
  Workflows       read and write   (to bump pinned actions and tool versions)

Not `Dependabot alerts`: .github/renovate.json turns vulnerabilityAlerts off.
Granting it and turning them on is one change, not two.

Create it from the repository owner's account: the workflow starts a run
from a dashboard edit only when the dashboard's author is the owner.

Then store it as a secret of the `renovate` environment, which the workflow
reads it from. The environment has to exist before a secret can be set in it:

  gh api -X PUT 'repos/{owner}/{repo}/environments/renovate'
  gh secret set RENOVATE_TOKEN --env renovate
EOF
exit 1
