// Decide: a Dependency Dashboard checkbox was newly ticked.
//
// Usage: BODY_BEFORE=… BODY_AFTER=… GITHUB_OUTPUT=… node renovate-tick.ts
//
// Renovate rewrites the dashboard on every pass with a personal access token,
// and a PAT's edit starts workflows, so `issues: edited` alone would run
// Renovate for ever. The actor cannot tell the two apart — the PAT acts as its
// owner — so this compares WHAT changed: proceed only when a checkbox carrying
// a Renovate marker went from unchecked to checked. Renovate un-ticks after
// acting, so its own rewrite never adds one.

import { info, setOutput } from "./lib/actions.ts";
import { optionalEnv } from "./lib/env.ts";
import { runMain } from "./lib/main.ts";

// OUTPUT is the output the Renovate steps read.
export const OUTPUT = "proceed";
// TICKED is a ticked task-list item; Renovate indents nested ones.
const TICKED = /^ *- \[x\]/;
// MARKER tags each actionable checkbox Renovate writes; a stray checkbox in
// prose has none.
const MARKER = "<!--";

// tickedBoxes is every ticked Renovate checkbox in body.
function tickedBoxes(body: string): string[] {
  return body.split(/\r?\n/).filter((line) => TICKED.test(line) && line.includes(MARKER));
}

// newlyTicked is each Renovate checkbox ticked in after and not in before.
// By content, not position — Renovate reorders the list as updates come and
// go — and counted, so a second copy of a line is a new tick.
export function newlyTicked(before: string, after: string): string[] {
  const remaining = new Map<string, number>();
  for (const line of tickedBoxes(before)) {
    remaining.set(line, (remaining.get(line) ?? 0) + 1);
  }
  const added: string[] = [];
  for (const line of tickedBoxes(after)) {
    const left = remaining.get(line) ?? 0;
    if (left > 0) {
      remaining.set(line, left - 1);
    } else {
      added.push(line);
    }
  }
  return added;
}

async function main(): Promise<void> {
  const added = newlyTicked(optionalEnv("BODY_BEFORE") ?? "", optionalEnv("BODY_AFTER") ?? "");
  setOutput(OUTPUT, String(added.length > 0));
  info(added.length === 0 ? "no Renovate checkbox was newly ticked — nothing to do" : `newly ticked:\n${added.join("\n")}`);
}

if (import.meta.main) {
  await runMain(main);
}
