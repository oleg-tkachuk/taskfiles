// Verify: the secrets gate asks gitleaks to say where, with values redacted.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-security-secrets.ts
//
// A shim records gitleaks' argv. What matters is the pair of flags: -v so a
// finding names its rule, file, line and commit, --redact so neither the
// secret nor the surrounding match reaches the log.

import { join } from "node:path";

import { commitAll, initRepo } from "./lib/git.ts";
import { runMain } from "./lib/main.ts";
import { expectArgs, lastCall, modulePath, passed, shim, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// FLAGS are the two gitleaks must get.
const FLAGS = ["--redact", "-v"];

async function main(): Promise<void> {
  const { dir, bin } = workspace("secretsgate");
  const argv = join(dir, "argv.json");
  shim(bin, "gitleaks", { record: argv });
  await initRepo(dir);
  writeTaskfile(dir, { sec: { taskfile: modulePath("security") } });
  await commitAll(dir, "seed");

  await taskOk(["sec:secrets"], { cwd: dir, path: [bin] });
  expectArgs(lastCall(argv), FLAGS, "gitleaks");
  passed("the secrets gate passes both --redact and -v");
}

if (import.meta.main) {
  await runMain(main);
}
