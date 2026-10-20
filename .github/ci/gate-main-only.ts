// Guard: releases only from main.
//
// Usage: TAG=<tag> node gate-main-only.ts, in a clone whose HEAD is the
// tagged commit.
//
// Consumers pin `?ref=vX.Y.Z` and fetch that exact tree, so a tag cut on a
// side branch would publish a tree main never held and CI on main never saw.
// HEAD rather than the tag ref: the checkout is already the tagged commit,
// under a tag push and a workflow_dispatch alike.

import { info } from "./lib/actions.ts";
import { requireEnv } from "./lib/env.ts";
import { git } from "./lib/git.ts";
import { runMain } from "./lib/main.ts";

// MAIN_REF is the remote-tracking ref of the release branch.
export const MAIN_REF = "refs/remotes/origin/main";
// FETCH_MAIN fetches it when the checkout did not.
const FETCH_MAIN = ["fetch", "--quiet", "origin", `main:${MAIN_REF}`];

// onMain reports whether main contains rev, fetching main first when this
// clone does not have it.
export async function onMain(rev: string, cwd?: string): Promise<boolean> {
  try {
    await git(["rev-parse", "--verify", "--quiet", MAIN_REF], cwd);
  } catch {
    await git(FETCH_MAIN, cwd);
  }
  try {
    await git(["merge-base", "--is-ancestor", rev, MAIN_REF], cwd);
    return true;
  } catch {
    return false;
  }
}

async function main(): Promise<void> {
  const tag = requireEnv("TAG");
  if (!(await onMain("HEAD"))) {
    throw new Error(
      `Releases must be cut from main. ${tag} points at a commit main does not contain, so it would publish a tree that never passed CI on main — and consumers pinning ?ref=${tag} would fetch exactly that tree.`,
    );
  }
  info(`✔ ${tag} is a commit on main`);
}

if (import.meta.main) {
  await runMain(main);
}
