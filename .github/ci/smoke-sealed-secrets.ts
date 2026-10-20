// Verify: sealed-secrets passes the context and paths as data.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-sealed-secrets.ts
//
// Shims for kubectl (records argv, prints a Secret) and kubeseal (passes it
// through). The context carries a command substitution that used to run; the
// output sits in a directory with a space; literals split into one
// --from-literal each.

import { existsSync } from "node:fs";
import { join } from "node:path";

import { runMain } from "./lib/main.ts";
import { SUBSTITUTION, expect, expectArgs, expectNotSubstituted, lastCall, modulePath, passed, shim, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// OUTPUT is the sealed file's path, a space in its directory.
const OUTPUT = "out dir/app.yaml";

async function main(): Promise<void> {
  const { dir, bin } = workspace("sealgate");
  const argv = join(dir, "argv.json");
  shim(bin, "kubectl", { record: argv, stdout: "kind: Secret\n" });
  shim(bin, "kubeseal", { stdin: "echo" });
  writeTaskfile(dir, { ss: { taskfile: modulePath("sealed-secrets") } });

  await taskOk(
    ["ss:seal:literals", "SECRET_NAME=app", "SECRET_NAMESPACE=prod", "SECRET_LITERALS=A=1 B=two", `SECRET_OUTPUT=${OUTPUT}`, `K8S_CONTEXT=dev${SUBSTITUTION}`],
    { cwd: dir, path: [bin] },
  );
  expectNotSubstituted(dir, "K8S_CONTEXT");
  expect(existsSync(join(dir, OUTPUT)), "the output path with a space was not honoured");
  expectArgs(lastCall(argv), ["--from-literal=A=1", "--from-literal=B=two"], "kubectl");
  passed("sealed-secrets passes the context and paths as data");
}

if (import.meta.main) {
  await runMain(main);
}
