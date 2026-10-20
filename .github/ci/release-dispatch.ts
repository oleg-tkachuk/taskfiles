// Dispatch release.yml for the commit this CI run checked.
//
// Usage: GH_TOKEN=… GITHUB_REPOSITORY=… GITHUB_SHA=… GITHUB_RUN_ID=… node release-dispatch.ts
//
// repository_dispatch is one of the documented exceptions that create a run
// from an event GITHUB_TOKEN caused — see release.yml. The payload names the
// commit and this run, which release.yml prints so the run says where it
// came from.

import { info } from "./lib/actions.ts";
import { requireEnv } from "./lib/env.ts";
import { gitHubFor, type GitHub } from "./lib/github.ts";
import { runMain } from "./lib/main.ts";

// RELEASE_EVENT is the repository_dispatch type release.yml runs on.
export const RELEASE_EVENT = "release";

// dispatchRelease asks for a release of sha, vouched for by CI run runId.
export async function dispatchRelease(github: GitHub, sha: string, runId: string): Promise<void> {
  await github.dispatch(RELEASE_EVENT, { sha, ci_run_id: runId });
  info(`dispatched release for ${sha}`);
}

async function main(): Promise<void> {
  const github = gitHubFor(requireEnv("GH_TOKEN"), requireEnv("GITHUB_REPOSITORY"));
  await dispatchRelease(github, requireEnv("GITHUB_SHA"), requireEnv("GITHUB_RUN_ID"));
}

if (import.meta.main) {
  await runMain(main);
}
