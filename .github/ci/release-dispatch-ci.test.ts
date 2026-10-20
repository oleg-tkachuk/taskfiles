import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { commitAll, git, initRepo } from "./lib/git.ts";
import { fakeData, fakeGitHub } from "./lib/fake-github.ts";
import { tempDir } from "./lib/temp-dir.ts";
import { CI_WORKFLOW, TAG_INPUT, dispatchCi, newTag } from "./release-dispatch-ci.ts";

test("reads the tag on HEAD, and none when HEAD is untagged", async () => {
  const tmp = tempDir();
  try {
    await initRepo(tmp.dir);
    await commitAll(tmp.dir, "first");
    assert.equal(await newTag(tmp.dir), undefined);
    await git(["tag", "v1.0.0"], tmp.dir);
    assert.equal(await newTag(tmp.dir), "v1.0.0");
  } finally {
    tmp.cleanup();
  }
});

test("dispatches CI for a new tag, and nothing without one", async () => {
  const data = fakeData();
  await dispatchCi(fakeGitHub(data), undefined, "main");
  assert.deepEqual(data.workflowRuns, []);
  await dispatchCi(fakeGitHub(data), "v1.0.0", "main");
  assert.deepEqual(data.workflowRuns, [{ workflow: CI_WORKFLOW, ref: "main", inputs: { [TAG_INPUT]: "v1.0.0" } }]);
});

test("ci.yml takes the tag in that input", () => {
  const workflow = parse(readFileSync(new URL(`../workflows/${CI_WORKFLOW}`, import.meta.url), "utf8")) as { on: { workflow_dispatch: { inputs: Record<string, unknown> } } };
  assert.ok(TAG_INPUT in workflow.on.workflow_dispatch.inputs);
});
