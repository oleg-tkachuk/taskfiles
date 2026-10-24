import assert from "node:assert/strict";
import { test } from "node:test";

import { commitAll, initRepo } from "./lib/git.ts";
import { tempDir } from "./lib/temp-dir.ts";
import { stillHead } from "./release-head.ts";

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
