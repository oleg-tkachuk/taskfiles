// Publish: the GitHub release for a tag.
//
// Usage: GH_TOKEN=… GITHUB_REPOSITORY=… TAG=<tag> node publish-release.ts
//
// Notes come from merged pull requests since the previous tag — see
// .github/release.yml. A release that already exists is left as it is, so a
// second run of the same verification says so rather than failing. The tag
// has to exist first: creating a release for a missing tag would create the
// tag too, at the default branch's head — a tree nothing verified.

import { info } from "./lib/actions.ts";
import { requireEnv } from "./lib/env.ts";
import { gitHubFor, type GitHub } from "./lib/github.ts";
import { runMain } from "./lib/main.ts";

// publish creates the release for tag unless it is already there.
export async function publish(github: GitHub, tag: string): Promise<void> {
  if (await github.releaseExists(tag)) {
    info(`✔ release ${tag} already exists`);
    return;
  }
  if (!(await github.tagExists(tag))) {
    throw new Error(`tag ${tag} is not in the repository; a release for it would create it on the default branch`);
  }
  // A tag-push run and a dispatched run can both reach this point; the one
  // that loses finds the release there, as a second run of the check would.
  if (!(await github.createRelease(tag))) {
    info(`✔ release ${tag} already exists`);
    return;
  }
  info(`✔ released ${tag}`);
}

async function main(): Promise<void> {
  await publish(gitHubFor(requireEnv("GH_TOKEN"), requireEnv("GITHUB_REPOSITORY")), requireEnv("TAG"));
}

if (import.meta.main) {
  await runMain(main);
}
