// The consumer the smoke and release checks build: a repository that
// includes the library the way the README tells one to.

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { commitAll, initRepo } from "./git.ts";

// VERSION_BASE is the consumer's own version base. release:version builds a
// dev version on it, which is how a check sees that a consumer's var reached
// the module that reads it.
export const VERSION_BASE = "9.9.9";
// DEV_VERSION_PREFIX begins every version release:version mints on it.
export const DEV_VERSION_PREFIX = `${VERSION_BASE}-dev.`;

// CONSUMER_DIR is where the consumer is built, under the step's directory.
export const CONSUMER_DIR = "consumer";
// TASKFILE is the file Task reads in a directory.
export const TASKFILE = "Taskfile.yaml";

// CONSUMER_VARS are the top-level vars a consumer sets for the modules.
const CONSUMER_VARS = {
  PROJECT_NAME: "smoke",
  IMAGE_NAMESPACE: "acme",
  K8S_NAMESPACE: "smoke-ns",
  REGISTRY: "registry.example.com",
  VERSION_BASE,
};

// Includes maps each include's alias to the module it names.
export type Includes = Readonly<Record<string, string>>;

// isDevVersion reports whether version is one release:version minted on
// VERSION_BASE.
export function isDevVersion(version: string): boolean {
  return version.startsWith(DEV_VERSION_PREFIX);
}

// consumerTaskfile is a consumer's Taskfile, including each module through
// tasklib, a printf pattern taking the module's path. JSON is YAML, and
// JSON.stringify quotes every value, so a value never changes the document.
export function consumerTaskfile(tasklib: string, includes: Includes): string {
  const document = {
    version: "3",
    silent: true,
    vars: { TASKLIB: tasklib, ...CONSUMER_VARS },
    includes: Object.fromEntries(Object.entries(includes).map(([alias, module]) => [alias, { taskfile: `{{printf .TASKLIB ${JSON.stringify(module)}}}`, dir: "." }])),
    tasks: {},
  };
  return `${JSON.stringify(document, null, 2)}\n`;
}

// SEED is the placeholder file a consumer's first commit holds.
const SEED = { file: "README.md", content: "placeholder\n" };

// seedConsumer makes dir a repository with one commit and the Taskfile.
export async function seedConsumer(dir: string, taskfile: string): Promise<void> {
  mkdirSync(dir, { recursive: true });
  await initRepo(dir);
  writeFileSync(join(dir, SEED.file), SEED.content);
  await commitAll(dir, "chore: seed");
  writeFileSync(join(dir, TASKFILE), taskfile);
}
