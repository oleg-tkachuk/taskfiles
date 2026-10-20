// Verify: codegen actually generates.
//
// Usage: node smoke-codegen-generate.ts, in the consumer.
//
// `go generate` is the one step of the chain that needs no external tool, so
// it is the one the library proves end to end — GOWORK=off included, which
// is what made generation fail for a real consumer before it was set.

import { existsSync, readFileSync } from "node:fs";

import { runMain } from "./lib/main.ts";
import { expect, passed, taskOk } from "./lib/smoke.ts";

// GENERATED is the file the fixture's directive writes, and what it holds.
const GENERATED = { file: "generated.go", marker: "const Generated = true" };

async function main(): Promise<void> {
  expect(!existsSync(GENERATED.file), `${GENERATED.file} is there before generation ran`);
  await taskOk(["codegen:generate"], { cwd: process.cwd() });
  expect(existsSync(GENERATED.file) && readFileSync(GENERATED.file, "utf8").includes(GENERATED.marker), `codegen:generate did not write ${GENERATED.file}`);
  passed("codegen:generate wrote the file its directive asks for");
}

if (import.meta.main) {
  await runMain(main);
}
