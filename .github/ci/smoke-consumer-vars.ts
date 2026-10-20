// Verify: the consumer's vars reach the modules.
//
// Usage: node smoke-consumer-vars.ts, in the consumer.
//
// A var declared in a module would shadow the consumer's; VERSION_BASE is the
// cheapest observable proof that none does.

import { isDevVersion } from "./lib/consumer.ts";
import { runMain } from "./lib/main.ts";
import { expect, passed, taskOk } from "./lib/smoke.ts";

async function main(): Promise<void> {
  const version = (await taskOk(["release:version"], { cwd: process.cwd() })).stdout.trim();
  expect(isDevVersion(version), "the consumer's VERSION_BASE did not reach release:version", version);
  passed(`consumer vars reach the modules (${version})`);
}

if (import.meta.main) {
  await runMain(main);
}
