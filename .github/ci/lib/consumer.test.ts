import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { parse } from "yaml";

import { DEV_VERSION_PREFIX, TASKFILE, VERSION_BASE, consumerTaskfile, isDevVersion, seedConsumer } from "./consumer.ts";
import { git } from "./git.ts";
import { tempDir } from "./temp-dir.ts";

test("the consumer includes each module through TASKLIB, and its vars are the README's", () => {
  const doc = parse(consumerTaskfile("../lib/%s", { release: "release", python: "python/poetry" })) as {
    vars: Record<string, string>;
    includes: Record<string, { taskfile: string; dir: string }>;
  };
  assert.equal(doc.vars.TASKLIB, "../lib/%s");
  assert.equal(doc.vars.VERSION_BASE, VERSION_BASE);
  assert.deepEqual(doc.includes.python, { taskfile: '{{printf .TASKLIB "python/poetry"}}', dir: "." });
});

test("a TASKLIB with a quote in it stays one value", () => {
  const tasklib = "https://github.com/o/r.git//%s?ref=v1'x\"";
  assert.equal((parse(consumerTaskfile(tasklib, {})) as { vars: { TASKLIB: string } }).vars.TASKLIB, tasklib);
});

test("isDevVersion takes a dev version on the base and nothing else", () => {
  assert.equal(isDevVersion(`${DEV_VERSION_PREFIX}123.gabc`), true);
  for (const other of ["9.9.9", "1.0.0-dev.1", "9.9.90-dev.1"]) {
    assert.equal(isDevVersion(other), false, other);
  }
});

test("seedConsumer leaves a repository with one commit and the Taskfile uncommitted", async () => {
  const tmp = tempDir();
  try {
    const dir = join(tmp.dir, "consumer");
    await seedConsumer(dir, "version: '3'\n");
    assert.equal((await git(["rev-list", "--count", "HEAD"], dir)).trim(), "1");
    assert.equal(readFileSync(join(dir, TASKFILE), "utf8"), "version: '3'\n");
    assert.equal(existsSync(join(dir, "README.md")), true);
  } finally {
    tmp.cleanup();
  }
});
