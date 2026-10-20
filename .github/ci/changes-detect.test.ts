import assert from "node:assert/strict";
import { test } from "node:test";

import { detect, smokeSkippable } from "./changes-detect.ts";
import { commitAll, initRepo } from "./lib/git.ts";
import { tempDir } from "./lib/temp-dir.ts";

const cases: [string, boolean, string[]][] = [
  ["docs only", true, ["README.md", "go/README.md"]],
  ["a workflow only", true, [".github/workflows/ci.yml"]],
  ["a CI command", false, [".github/ci/smoke-auth.ts"]],
  ["a CI command beside docs", false, [".github/ci/lib/smoke.ts", "README.md"]],
  ["the action that sets the CI scripts up", false, [".github/actions/setup-ci/action.yml"]],
  ["a module", false, ["go/Taskfile.yaml"]],
  ["a module beside a workflow", false, ["go/Taskfile.yaml", ".github/workflows/ci.yml"]],
  ["nothing", false, []],
];
for (const [name, want, paths] of cases) {
  test(`skippable: ${name}`, () => assert.equal(smokeSkippable(paths), want));
}

test("decides on the diff between two commits, and on no base runs everything", async () => {
  const tmp = tempDir();
  try {
    await initRepo(tmp.dir);
    tmp.write("README.md", "x\n");
    tmp.write("go/Taskfile.yaml", "x\n");
    const base = await commitAll(tmp.dir, "base");
    tmp.write("README.md", "y\n");
    const docs = await commitAll(tmp.dir, "docs");
    tmp.write("go/Taskfile.yaml", "y\n");
    const module = await commitAll(tmp.dir, "module");

    assert.deepEqual(await detect(base, docs, tmp.dir), { skippable: true, changed: ["README.md"] });
    assert.equal((await detect(docs, module, tmp.dir)).skippable, false);
    assert.deepEqual(await detect(undefined, module, tmp.dir), { skippable: false, changed: undefined });
    assert.deepEqual(await detect("0000000000000000000000000000000000000000", module, tmp.dir), { skippable: false, changed: undefined });
  } finally {
    tmp.cleanup();
  }
});
