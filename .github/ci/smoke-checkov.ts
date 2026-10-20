// Verify: checkov passes its flags through and treats the version as data.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-checkov.ts
//
// A shim answers --version and records the scan's argv. CHECKOV_FLAGS is
// shell by contract and must arrive as flags; CHECKOV_VERSION is data — a
// command substitution in it used to run.

import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { runMain } from "./lib/main.ts";
import { SUBSTITUTION, expectArgs, expectNotSubstituted, lastCall, modulePath, passed, shim, task, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// FLAGS are what CHECKOV_FLAGS carries.
const FLAGS = ["--quiet", "--skip-download"];
// INSTALLED is the version the shim reports.
const INSTALLED = "3.3.27";
// CONFIG is the smallest config the scan accepts.
const CONFIG = { file: ".checkov.yaml", content: "directory: [.]\n" };

async function main(): Promise<void> {
  const { dir, bin } = workspace("checkovgate");
  const argv = join(dir, "argv.json");
  shim(bin, "checkov", { replies: { "--version": `${INSTALLED}\n` }, record: argv });
  writeFileSync(join(dir, CONFIG.file), CONFIG.content);
  writeTaskfile(dir, { ckv: { taskfile: modulePath("checkov"), vars: { CHECKOV_FLAGS: FLAGS.join(" ") } } });
  const options = { cwd: dir, path: [bin] };

  await taskOk(["ckv:scan"], options);
  expectArgs(lastCall(argv), FLAGS, "CHECKOV_FLAGS");
  passed("checkov passes CHECKOV_FLAGS through as flags");

  // Whether the scan runs does not matter here, only whether the shell did.
  await task(["ckv:scan", `CHECKOV_VERSION=${SUBSTITUTION}`], options);
  expectNotSubstituted(dir, "CHECKOV_VERSION");
  passed("checkov treats CHECKOV_VERSION as data");
}

if (import.meta.main) {
  await runMain(main);
}
