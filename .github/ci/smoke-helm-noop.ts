// Verify: helm no-ops cleanly with no cluster.
//
// Usage: node smoke-helm-noop.ts, in the consumer.
//
// helm:list's status guard skips it when kubectl cannot reach a cluster,
// which is always so here: this proves the guard, not the listing.

import { runMain } from "./lib/main.ts";
import { passed, taskOk } from "./lib/smoke.ts";

async function main(): Promise<void> {
  await taskOk(["helm:list"], { cwd: process.cwd() });
  passed("helm:list no-ops without a reachable cluster");
}

if (import.meta.main) {
  await runMain(main);
}
