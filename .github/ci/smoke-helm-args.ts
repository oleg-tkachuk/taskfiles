// Verify: helm passes the context and namespace as single arguments.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-helm-args.ts
//
// Shims for kubectl (a reachable cluster) and helm (records argv). The
// context and namespace are data: one argument each, never parsed — a command
// substitution in the context used to run, and a namespace with a space used
// to split.

import { join } from "node:path";

import { runMain } from "./lib/main.ts";
import { SUBSTITUTION, expectArgs, expectNotSubstituted, lastCall, modulePath, passed, shim, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// CONTEXT and NAMESPACE are the values that must each arrive whole.
const CONTEXT = `dev${SUBSTITUTION}`;
const NAMESPACE = "my ns";

async function main(): Promise<void> {
  const { dir, bin } = workspace("helmgate");
  const argv = join(dir, "argv.json");
  shim(bin, "kubectl", {});
  shim(bin, "helm", { record: argv });
  writeTaskfile(dir, { helm: { taskfile: modulePath("helm") } });

  await taskOk(["helm:list", `K8S_CONTEXT=${CONTEXT}`, `HELM_NS=${NAMESPACE}`], { cwd: dir, path: [bin] });
  expectNotSubstituted(dir, "K8S_CONTEXT");
  expectArgs(lastCall(argv), [CONTEXT, NAMESPACE], "helm");
  passed("helm passes the context and namespace as single arguments");
}

if (import.meta.main) {
  await runMain(main);
}
