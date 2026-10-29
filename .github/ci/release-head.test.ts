import assert from "node:assert/strict";
import { test } from "node:test";

import { runCommand } from "./lib/command.ts";
import { commitAll, initRepo } from "./lib/git.ts";
import { tempDir } from "./lib/temp-dir.ts";
import { DUE, stillHead } from "./release-head.ts";

test("the commit CI passed is due only while it is still the checked-out head", async () => {
  const tmp = tempDir();
  try {
    await initRepo(tmp.dir);
    tmp.write("a", "1\n");
    const passed = await commitAll(tmp.dir, "passed CI");
    assert.equal(await stillHead(passed, tmp.dir), true);

    // main moved on before the release run checked it out.
    tmp.write("b", "2\n");
    await commitAll(tmp.dir, "landed after");
    assert.equal(await stillHead(passed, tmp.dir), false);

    // A dispatch that names no commit vouches for none.
    assert.equal(await stillHead(undefined, tmp.dir), false);
  } finally {
    tmp.cleanup();
  }
});

test("the command sets due for the checked-out head, and stands down for any other", async () => {
  const tmp = tempDir();
  try {
    await initRepo(tmp.dir);
    tmp.write("a", "1\n");
    const head = await commitAll(tmp.dir, "head");

    const due = await runCommand("release-head.ts", { cwd: tmp.dir, env: { SHA: head, CI_RUN: "42" } });
    assert.equal(due.code, 0);
    assert.deepEqual(due.outputs, { [DUE]: "true" });
    assert.match(due.stdout, new RegExp(`dispatched by CI run 42 for commit ${head}`));

    const moved = await runCommand("release-head.ts", { cwd: tmp.dir, env: { SHA: "0".repeat(40) } });
    assert.deepEqual(moved.outputs, { [DUE]: "false" });
    assert.match(moved.stdout, /dispatched by CI run unknown/);
    assert.match(moved.stdout, /main is no longer 0+; the CI run of what is there now releases it/);

    const unnamed = await runCommand("release-head.ts", { cwd: tmp.dir });
    assert.deepEqual(unnamed.outputs, { [DUE]: "false" });
    assert.match(unnamed.stdout, /main is no longer a named commit/);
  } finally {
    tmp.cleanup();
  }
});
