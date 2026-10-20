// Verify: runtime install passes every value as one argument.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-runtime-install.ts
//
// kind as the representative: the runtime variants share this shape, and
// check:runtime holds them to it. The namespace and values path carry
// spaces, the service name a command substitution that used to run, and
// HELM_UPGRADE_FLAGS is shell by contract and must arrive as flags.

import { join } from "node:path";

import { runMain } from "./lib/main.ts";
import { SUBSTITUTION, expectArgs, expectNotSubstituted, lastCall, modulePath, passed, shim, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// NAMESPACE, VALUES, FLAGS and VERSION are the inputs whose arguments are
// checked; the image tag is how VERSION reaches helm.
const NAMESPACE = "my ns";
const VALUES = "my values.yaml";
const FLAGS = ["--wait", "--atomic"];
const VERSION = "1.2.3";

async function main(): Promise<void> {
  const { dir, bin } = workspace("runtimegate");
  const argv = join(dir, "argv.json");
  // `kind get clusters` names the cluster the module expects to find.
  shim(bin, "kind", { replies: { get: "kind\n" } });
  shim(bin, "helm", { record: argv });
  writeTaskfile(dir, { rt: { taskfile: modulePath("runtime/kind") } });

  await taskOk(
    [
      "rt:install",
      `PROJECT_NAME=svc${SUBSTITUTION}`,
      `K8S_NAMESPACE=${NAMESPACE}`,
      `VALUES=${VALUES}`,
      `HELM_UPGRADE_FLAGS=${FLAGS.join(" ")}`,
      "_REL_IMAGE=img",
      `_REL_VERSION=${VERSION}`,
    ],
    { cwd: dir, path: [bin] },
  );
  expectNotSubstituted(dir, "PROJECT_NAME");
  expectArgs(lastCall(argv), [NAMESPACE, VALUES, ...FLAGS, `image.tag=${VERSION}`], "helm");
  passed("runtime install passes every value as one argument");
}

if (import.meta.main) {
  await runMain(main);
}
