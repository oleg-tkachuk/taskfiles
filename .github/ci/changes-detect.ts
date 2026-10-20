// Decide: does this change touch anything outside docs and workflows?
//
// Usage: EVENT=… BASE=<sha> HEAD=<sha> GITHUB_OUTPUT=… node changes-detect.ts
//
// Feeds consumer-smoke's per-step `if:`. Docs and workflow configuration
// cannot change what consumer-smoke proves; the CI scripts and the action
// that sets them up are the smoke steps themselves, so a change there does.
// Anything short of "every changed file is irrelevant" — no base to diff
// against included — runs the full matrix.

import { info, setOutput } from "./lib/actions.ts";
import { optionalEnv, requireEnv } from "./lib/env.ts";
import { changedPaths, hasCommit } from "./lib/git.ts";
import { runMain } from "./lib/main.ts";

// OUTPUT is the output consumer-smoke reads.
export const OUTPUT = "smoke_skippable";
// SMOKE_PATHS hold what consumer-smoke runs, though they sit under .github/.
export const SMOKE_PATHS: readonly string[] = [".github/ci/", ".github/actions/"];
// IRRELEVANT_DIR and IRRELEVANT_SUFFIX are what consumer-smoke never reads.
const IRRELEVANT_DIR = ".github/";
const IRRELEVANT_SUFFIX = ".md";

// isRelevant reports whether a change to path can change what consumer-smoke
// proves.
export function isRelevant(path: string): boolean {
  if (SMOKE_PATHS.some((prefix) => path.startsWith(prefix))) {
    return true;
  }
  return !path.startsWith(IRRELEVANT_DIR) && !path.endsWith(IRRELEVANT_SUFFIX);
}

// smokeSkippable reports whether a change to paths lets consumer-smoke skip:
// some paths changed and none of them is relevant.
export function smokeSkippable(paths: readonly string[]): boolean {
  return paths.length > 0 && !paths.some(isRelevant);
}

// Decision is whether consumer-smoke may skip, and the change it was decided
// on; changed is undefined when there was no base to diff against.
export interface Decision {
  skippable: boolean;
  changed: string[] | undefined;
}

// detect is the decision for a change from base to head in cwd; with no base
// this clone holds, it is false.
export async function detect(base: string | undefined, head: string, cwd?: string): Promise<Decision> {
  if (base === undefined || !(await hasCommit(base, cwd))) {
    return { skippable: false, changed: undefined };
  }
  const changed = await changedPaths(base, head, cwd);
  return { skippable: smokeSkippable(changed), changed };
}

async function main(): Promise<void> {
  const { skippable, changed } = await detect(optionalEnv("BASE"), requireEnv("HEAD"));
  setOutput(OUTPUT, String(skippable));
  if (changed === undefined) {
    info(`no usable base for ${optionalEnv("EVENT") ?? "this event"} — running the full matrix`);
    return;
  }
  info(`changed files:\n${changed.length === 0 ? "<none>" : changed.join("\n")}`);
}

if (import.meta.main) {
  await runMain(main);
}
