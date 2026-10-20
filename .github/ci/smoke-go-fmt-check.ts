// Verify: go:fmt:check catches what go:fmt would rewrite.
//
// Usage: node smoke-go-fmt-check.ts, in the consumer.
//
// gofmt -l exits 0 whether or not it lists a file, so a wrapper that only
// asked "did it run" would pass dirty code every time.

import { rmSync, writeFileSync } from "node:fs";

import { runMain } from "./lib/main.ts";
import { passed, taskFails, taskOk } from "./lib/smoke.ts";

// UNFORMATTED is a file gofmt -l lists.
const UNFORMATTED = { file: "badfmt.go", content: "package smoke\nfunc   Bad ( )   {}\n" };

async function main(): Promise<void> {
  const cwd = process.cwd();
  writeFileSync(UNFORMATTED.file, UNFORMATTED.content);
  await taskFails(["go:fmt:check"], { cwd }, "on a file gofmt -l would list");
  rmSync(UNFORMATTED.file);
  await taskOk(["go:fmt:check"], { cwd });
  passed("go:fmt:check fails on unformatted code and passes on clean code");
}

if (import.meta.main) {
  await runMain(main);
}
