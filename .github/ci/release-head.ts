// Guard: release only the commit CI vouched for.
//
// Usage: SHA=<commit> [CI_RUN=<run id>] node release-head.ts, in the release
// job's checkout. Sets the output `due`, which every release step is gated on.
//
// The checkout is main's head, not the dispatched sha: semantic-release has to
// be on a branch to release at all. main can move between CI passing and this
// run starting, and releasing then would tag a commit whose own CI is still
// running, or failed. That commit's CI dispatches its own release once it
// passes, so this run stands down rather than going red.

import { info, setOutput } from "./lib/actions.ts";
import { optionalEnv } from "./lib/env.ts";
import { git } from "./lib/git.ts";
import { runMain } from "./lib/main.ts";

// DUE is the output the release steps read.
export const DUE = "due";

// stillHead reports whether sha is the commit checked out in cwd. No sha is
// never due: a dispatch that names no commit vouches for none.
export async function stillHead(sha: string | undefined, cwd?: string): Promise<boolean> {
  if (sha === undefined) {
    return false;
  }
  return (await git(["rev-parse", "HEAD"], cwd)).trim() === sha;
}

async function main(): Promise<void> {
  const sha = optionalEnv("SHA");
  // A dispatched run is not linked to its trigger in the UI the way a
  // workflow_run is, so without this line it says nothing of where it came from.
  info(`dispatched by CI run ${optionalEnv("CI_RUN") ?? "unknown"} for commit ${sha ?? "unknown"}`);
  const due = await stillHead(sha);
  if (!due) {
    info(`main is no longer ${sha ?? "a named commit"}; the CI run of what is there now releases it`);
  }
  setOutput(DUE, String(due));
}

if (import.meta.main) {
  await runMain(main);
}
