// Verify: the tag includes the way a consumer does.
//
// Usage: REPO=<owner/name> TAG=<tag> node consumable-include.ts
//
// Deliberately NOT the local checkout: this is the only check that proves the
// published tag can be fetched, that every module resolves through the git
// include path, and that the trust prompt does not block CI. --yes accepts
// that prompt; unattended, it is a hang rather than a question.

import { join } from "node:path";

import { CONSUMER_DIR, consumerTaskfile, isDevVersion, seedConsumer, type Includes } from "./lib/consumer.ts";
import { requireEnv } from "./lib/env.ts";
import { runMain } from "./lib/main.ts";
import { expect, passed, taskOk } from "./lib/smoke.ts";

// INCLUDES are the modules a consumer fetches over git: one of each family.
export const INCLUDES: Includes = {
  release: "release",
  k8s: "k8s",
  go: "go",
  python: "python/poetry",
  node: "node",
  compose: "compose",
  security: "security",
  monorepo: "monorepo",
  argocd: "argocd",
  auth: "auth",
  local: "runtime/orbstack",
};

// remoteTasklib is the include pattern for repo at tag, over git.
export function remoteTasklib(repo: string, tag: string): string {
  return `https://github.com/${repo}.git//%s?ref=${tag}`;
}

async function main(): Promise<void> {
  const dir = join(process.cwd(), CONSUMER_DIR);
  await seedConsumer(dir, consumerTaskfile(remoteTasklib(requireEnv("REPO"), requireEnv("TAG")), INCLUDES));
  await taskOk(["--yes", "--list-all"], { cwd: dir });
  const version = (await taskOk(["--yes", "release:version"], { cwd: dir })).stdout.trim();
  expect(isDevVersion(version), "the published tag does not resolve the consumer's VERSION_BASE", version);
  passed(`the published tag includes and resolves (${version})`);
}

if (import.meta.main) {
  await runMain(main);
}
