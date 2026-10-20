// Verify: pnpm:pin:check catches a pnpm shadowing the shim.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-pnpm-pin-check.ts
//
// The shadowing pnpm is the pinned version itself, so a check that only
// compares versions passes — which is the blind spot this closes. The same
// PATH with the shim first must still pass.

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { COREPACK_HOME, setUpPnpm } from "./lib/corepack.ts";
import { runMain } from "./lib/main.ts";
import { expect, modulePath, passed, taskFails, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// PIN is the version the app pins and the standalone pnpm runs.
const PIN = "12.7.0";
// APP is the app directory; SHADOWED, what the check says about the shadow.
const APP = "app";
const SHADOWED = "is not corepack's shim";

async function main(): Promise<void> {
  const { dir } = workspace("pnpm-shadow");
  const pnpm = await setUpPnpm(dir, PIN);
  mkdirSync(join(dir, APP), { recursive: true });
  writeFileSync(join(dir, APP, "package.json"), `${JSON.stringify({ name: "shadow", private: true, packageManager: `pnpm@${PIN}` })}\n`);
  writeTaskfile(dir, { pnpm: { taskfile: modulePath("pnpm"), vars: { PNPM_APPS: [APP] } } });
  const env = { [COREPACK_HOME]: pnpm.corepackHome };

  const shadowed = await taskFails(["pnpm:pin:check"], { cwd: dir, path: [pnpm.standalone, pnpm.shims], env }, "with a standalone pnpm ahead of the shim");
  expect(shadowed.stderr.includes(SHADOWED), "pin:check failed, but not on the shadowing", shadowed.stderr);
  await taskOk(["pnpm:pin:check"], { cwd: dir, path: [pnpm.shims, pnpm.standalone], env });
  passed("pin:check fails on a shadowing pnpm and passes with the shim first");
}

if (import.meta.main) {
  await runMain(main);
}
