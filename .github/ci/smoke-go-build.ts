// Verify: the go module formats, compiles, tests and tidies.
//
// Usage: node smoke-go-build.ts, in the consumer.
//
// `build` is left out: GO_MAIN defaults to ./cmd/..., which the fixture does
// not have, and a package with no main is the shape most consumers of the
// other tasks are.

import { runMain } from "./lib/main.ts";
import { passed, taskOk } from "./lib/smoke.ts";

// TASKS run in order, each against the fixture module.
const TASKS = ["go:fmt", "go:fmt:check", "go:compile", "go:test", "go:tidy"];

async function main(): Promise<void> {
  for (const name of TASKS) {
    await taskOk([name], { cwd: process.cwd() });
  }
  passed("the go module's tasks run against a real module");
}

if (import.meta.main) {
  await runMain(main);
}
