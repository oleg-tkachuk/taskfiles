import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";

import { onMain } from "./gate-main-only.ts";
import { commitAll, git, initRepo } from "./lib/git.ts";
import { tempDir } from "./lib/temp-dir.ts";

test("a commit main holds passes, one on a side branch does not — main fetched when the clone lacks it", async () => {
  const tmp = tempDir();
  try {
    const origin = join(tmp.dir, "origin");
    await initRepo(origin);
    tmp.write("origin/a", "1\n");
    const onMainCommit = await commitAll(origin, "on main");
    await git(["switch", "--quiet", "-c", "side"], origin);
    tmp.write("origin/b", "2\n");
    const sideCommit = await commitAll(origin, "on a side branch");

    // A clone that has the side branch and no remote-tracking main, as a tag
    // checkout leaves it.
    const clone = join(tmp.dir, "clone");
    await git(["clone", "--quiet", "--single-branch", "--branch", "side", origin, clone]);
    assert.equal(await onMain(sideCommit, clone), false);
    assert.equal(await onMain(onMainCommit, clone), true);
  } finally {
    tmp.cleanup();
  }
});
