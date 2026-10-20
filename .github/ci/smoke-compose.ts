// Verify: compose splits the engine and keeps the file whole.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-compose.ts
//
// COMPOSE_ENGINE is shell by contract — "podman compose" is a command and its
// first argument — while COMPOSE_FILE is data and must arrive as one argument
// even with a space in it. A shim stands in for podman.

import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { runMain } from "./lib/main.ts";
import { expect, expectArgs, lastCall, modulePath, passed, shim, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// COMPOSE_FILE has a space in its name; SERVICE is the one the logs are for.
const COMPOSE_FILE = "my compose.yaml";
const SERVICE = "web";

async function main(): Promise<void> {
  const { dir, bin } = workspace("composegate");
  const argv = join(dir, "argv.json");
  shim(bin, "podman", { record: argv });
  writeFileSync(join(dir, COMPOSE_FILE), "");
  writeTaskfile(dir, { cmp: { taskfile: modulePath("compose"), vars: { COMPOSE_ENGINE: "podman compose", COMPOSE_FILE } } });

  await taskOk(["cmp:logs", `SERVICE=${SERVICE}`], { cwd: dir, path: [bin] });
  const call = lastCall(argv);
  const head = ["compose", "-f", COMPOSE_FILE];
  expect(head.every((arg, i) => call[i] === arg), "the engine or the file did not arrive as meant", call);
  expectArgs(call, [SERVICE], "SERVICE");
  passed("compose splits the engine and keeps the file whole");
}

if (import.meta.main) {
  await runMain(main);
}
