// Guard: RENOVATE_TOKEN is set.
//
// Usage: RENOVATE_TOKEN=… node renovate-require-token.ts
//
// Fails with a sentence rather than with Renovate's own authentication error,
// which names neither the secret nor the permissions it needs.

import { info } from "./lib/actions.ts";
import { optionalEnv } from "./lib/env.ts";
import { runMain } from "./lib/main.ts";

// TOKEN_VAR is the secret, and the variable the step hands it in.
export const TOKEN_VAR = "RENOVATE_TOKEN";

// HOW_TO_SET_IT says what the token needs and where it goes.
export const HOW_TO_SET_IT = `Renovate needs a token of its own. GITHUB_TOKEN cannot be used: a pull
request opened with it does not trigger \`pull_request\` workflows, so no
required check would ever report and branch protection would block the merge
for ever.

Create a fine-grained personal access token scoped to this repository with:

  Contents        read and write
  Pull requests   read and write
  Issues          read and write   (the Dependency Dashboard)
  Workflows       read and write   (to bump pinned actions and tool versions)

Not \`Dependabot alerts\`: .github/renovate.json turns vulnerabilityAlerts off.
Granting it and turning them on is one change, not two.

Create it from the repository owner's account: the workflow starts a run
from a dashboard edit only when the dashboard's author is the owner.

Then store it as a secret of the \`renovate\` environment, which the workflow
reads it from. The environment has to exist before a secret can be set in it:

  gh api -X PUT 'repos/{owner}/{repo}/environments/renovate'
  gh secret set ${TOKEN_VAR} --env renovate`;

// requireToken throws, saying how to set it, when token is missing.
export function requireToken(token: string | undefined): void {
  if (token === undefined) {
    info(HOW_TO_SET_IT);
    throw new Error(`the ${TOKEN_VAR} secret is not set`);
  }
}

async function main(): Promise<void> {
  requireToken(optionalEnv(TOKEN_VAR));
}

if (import.meta.main) {
  await runMain(main);
}
