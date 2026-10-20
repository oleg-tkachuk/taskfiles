// Release the tag semantic-release just pushed.
//
// Usage: GH_TOKEN=… GITHUB_REPOSITORY=… GITHUB_REF_NAME=<branch> node release-dispatch-ci.ts,
// in the clone semantic-release ran in.
//
// semantic-release pushes the tag with GITHUB_TOKEN, and GitHub starts no run
// from that push — so ci.yml's tag path is dispatched here, with the tag as
// its input, the other documented exception that always creates a run. The
// tag is read from git rather than from semantic-release's prose: it tags
// the commit that was checked out, so no new tag means no release was due.

import { info } from "./lib/actions.ts";
import { requireEnv } from "./lib/env.ts";
import { git, lines } from "./lib/git.ts";
import { gitHubFor, type GitHub } from "./lib/github.ts";
import { runMain } from "./lib/main.ts";

// CI_WORKFLOW is the workflow that verifies and publishes a tag; TAG_INPUT,
// the input it takes the tag in.
export const CI_WORKFLOW = "ci.yml";
export const TAG_INPUT = "tag";

// newTag is the first tag pointing at HEAD in cwd, if any.
export async function newTag(cwd?: string): Promise<string | undefined> {
  return lines(await git(["tag", "--points-at", "HEAD"], cwd))[0];
}

// dispatchCi starts CI_WORKFLOW on ref for tag, or says why there is
// nothing to start.
export async function dispatchCi(github: GitHub, tag: string | undefined, ref: string): Promise<void> {
  if (tag === undefined) {
    info("no new tag on this commit — no release was due");
    return;
  }
  info(`dispatching ${CI_WORKFLOW} to verify and publish ${tag}`);
  await github.runWorkflow(CI_WORKFLOW, ref, { [TAG_INPUT]: tag });
}

async function main(): Promise<void> {
  const github = gitHubFor(requireEnv("GH_TOKEN"), requireEnv("GITHUB_REPOSITORY"));
  await dispatchCi(github, await newTag(), requireEnv("GITHUB_REF_NAME"));
}

if (import.meta.main) {
  await runMain(main);
}
