// Guard: the tag is SemVer.
//
// Usage: TAG=<tag> node gate-semver.ts
//
// Helm and OCI both reject a chart version that is not SemVer 2, and the
// modules mint chart versions from these tags. A tag that cannot be a chart
// version is a tag no consumer can use.

import { info } from "./lib/actions.ts";
import { requireEnv } from "./lib/env.ts";
import { runMain } from "./lib/main.ts";

// TAG_PREFIX begins every release tag.
export const TAG_PREFIX = "v";
// SEMVER is the regular expression semver.org publishes for a version, as is.
const SEMVER =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/;

// isReleaseTag reports whether tag is TAG_PREFIX and a SemVer 2 version.
export function isReleaseTag(tag: string): boolean {
  return tag.startsWith(TAG_PREFIX) && SEMVER.test(tag.slice(TAG_PREFIX.length));
}

async function main(): Promise<void> {
  const tag = requireEnv("TAG");
  if (!isReleaseTag(tag)) {
    throw new Error(`${tag} is not ${TAG_PREFIX}MAJOR.MINOR.PATCH`);
  }
  info(`✔ ${tag} is SemVer`);
}

if (import.meta.main) {
  await runMain(main);
}
