// Verify: pnpm:pin:update survives a postinstall that calls pnpm.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-pnpm-pin-update.ts
//
// The machine this broke on had a standalone pnpm ahead of corepack's shim. A
// postinstall calling `pnpm` inside `corepack use` reached that one, which
// refuses to switch versions under corepack, and the bump failed after
// corepack had already rewritten "packageManager". This builds that PATH,
// then asserts the pin moved AND the postinstall ran on the new version —
// skipping the script outright would pass the first half and fail the second.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { COREPACK_HOME, setUpPnpm } from "./lib/corepack.ts";
import { runMain } from "./lib/main.ts";
import { expect, modulePath, passed, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// PIN_FROM is the version pinned before, and the standalone one; PIN_TO, the
// version the update moves to.
const PIN_FROM = "12.4.0";
const PIN_TO = "12.7.0";
// APP is the app directory; MARKER, the file its postinstall writes the pnpm
// version it ran under to.
const APP = "app";
const MARKER = "postinstall-ran.txt";
// LOCKFILE is what the update must leave behind.
const LOCKFILE = "pnpm-lock.yaml";
// INTEGRITY begins the hash corepack appends to a pin it writes.
const INTEGRITY = "+sha512.";

async function main(): Promise<void> {
  const { dir } = workspace("pnpm-smoke");
  const pnpm = await setUpPnpm(dir, PIN_FROM);
  const app = join(dir, APP);
  mkdirSync(app, { recursive: true });
  writeFileSync(
    join(app, "package.json"),
    `${JSON.stringify({ name: "smoke", private: true, packageManager: `pnpm@${PIN_FROM}`, scripts: { postinstall: `pnpm --version > ${MARKER}` } })}\n`,
  );
  writeTaskfile(dir, { pnpm: { taskfile: modulePath("pnpm"), vars: { PNPM_APPS: [APP] } } });

  await taskOk(["pnpm:pin:update:major", "--", PIN_TO], { cwd: dir, path: [pnpm.standalone, pnpm.shims], env: { [COREPACK_HOME]: pnpm.corepackHome } });
  const pin = (JSON.parse(readFileSync(join(app, "package.json"), "utf8")) as { packageManager?: string }).packageManager ?? "";
  expect(pin.startsWith(`pnpm@${PIN_TO}${INTEGRITY}`), `packageManager is not pnpm@${PIN_TO} with its hash`, pin);
  expect(existsSync(join(app, LOCKFILE)), "pin:update wrote no lockfile");
  const ran = existsSync(join(app, MARKER)) ? readFileSync(join(app, MARKER), "utf8").trim() : "nothing";
  expect(ran === PIN_TO, `postinstall ran as ${ran}, want ${PIN_TO}`);
  passed(`pin:update moved the pin and ran postinstall on ${PIN_TO}`);
}

if (import.meta.main) {
  await runMain(main);
}
