// Verify: auth passes its flags through and refuses a TTL that is not a
// number.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-auth.ts
//
// A shim records step's argv. STEP_FLAGS is shell by contract and must
// arrive split into flags. The TTL goes into $(( )), which evaluates text as
// an expression, so anything but digits must be refused before it gets there.

import { join } from "node:path";

import { runMain } from "./lib/main.ts";
import { SUBSTITUTION, expect, expectArgs, expectNotSubstituted, lastCall, modulePath, passed, shim, taskFails, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// FLAGS are what STEP_FLAGS carries, each of which must reach step whole.
const FLAGS = ["--no-password", "--insecure"];
// REFUSAL is what auth says about a TTL that is not a number.
const REFUSAL = "must be a whole number";

async function main(): Promise<void> {
  const { dir, bin } = workspace("authgate");
  const argv = join(dir, "argv.json");
  shim(bin, "step", { record: argv, stdin: "drain" });
  writeTaskfile(dir, { auth: { taskfile: modulePath("auth") } });
  const options = { cwd: dir, path: [bin] };

  await taskOk(["auth:mint-token", "JWT_TTL_SECONDS=60", `STEP_FLAGS=${FLAGS.join(" ")}`], options);
  expectArgs(lastCall(argv), FLAGS, "STEP_FLAGS");
  passed("auth passes STEP_FLAGS through as flags");

  const refused = await taskFails(["auth:mint-token", `JWT_TTL_SECONDS=0 + ${SUBSTITUTION}`], options, "a TTL that is not a number");
  expectNotSubstituted(dir, "the TTL");
  expect(refused.stderr.includes(REFUSAL), `auth did not say the TTL ${REFUSAL}`, refused.stderr);
  passed("auth refuses a TTL that is not a number, without running it");
}

if (import.meta.main) {
  await runMain(main);
}
