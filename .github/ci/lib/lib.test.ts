import assert from "node:assert/strict";
import { readFileSync, renameSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { escapeData, setOutput } from "./actions.ts";
import { optionalEnv, requireEnv } from "./env.ts";
import { capture, execute } from "./exec.ts";
import { changedPaths, commitAll, hasCommit, initRepo, lines } from "./git.ts";
import { RequestError } from "octokit";

import { alreadyExists, splitRepository } from "./github.ts";
import { tempDir } from "./temp-dir.ts";

// withEnv runs fn with name set to value, restoring it after.
function withEnv(name: string, value: string | undefined, fn: () => void): void {
  const before = process.env[name];
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
  try {
    fn();
  } finally {
    if (before === undefined) delete process.env[name];
    else process.env[name] = before;
  }
}

test("requireEnv refuses an unset or empty variable by name; optionalEnv reads both as absent", () => {
  withEnv("TASKFILES_CI_TEST", "", () => {
    assert.throws(() => requireEnv("TASKFILES_CI_TEST"), /TASKFILES_CI_TEST is not set/);
    assert.equal(optionalEnv("TASKFILES_CI_TEST"), undefined);
  });
  withEnv("TASKFILES_CI_TEST", "x", () => {
    assert.equal(requireEnv("TASKFILES_CI_TEST"), "x");
    assert.equal(optionalEnv("TASKFILES_CI_TEST"), "x");
  });
});

test("setOutput appends name=value, and refuses a value that spans lines", () => {
  const tmp = tempDir();
  try {
    const file = tmp.write("output", "");
    withEnv("GITHUB_OUTPUT", file, () => {
      setOutput("a", "1");
      setOutput("b", "two words");
      assert.throws(() => setOutput("c", "x\nc=injected"), /spans lines/);
    });
    assert.equal(readFileSync(file, "utf8"), "a=1\nb=two words\n");
  } finally {
    tmp.cleanup();
  }
});

test("escapeData keeps a message from ending its workflow command", () => {
  assert.equal(escapeData("50%\r\n::error::x"), "50%25%0D%0A::error::x");
});

test("capture reports the exit code; execute throws with standard error", async () => {
  assert.deepEqual(await capture(process.execPath, ["-e", "process.stdout.write('out'); process.exit(4)"]), { code: 4, stdout: "out", stderr: "" });
  await assert.rejects(execute(process.execPath, ["-e", "console.error('why'); process.exit(2)"]), /exited with 2: why/);
  await assert.rejects(capture("/nonexistent/command", []), /could not be run/);
});

test("lines drops empty lines", () => {
  assert.deepEqual(lines("a\n\nb\n"), ["a", "b"]);
});

test("changedPaths lists a rename by both paths; hasCommit tells a commit from garbage", async () => {
  const tmp = tempDir();
  try {
    await initRepo(tmp.dir);
    tmp.write("old.txt", "x\n");
    const base = await commitAll(tmp.dir, "base");
    renameSync(join(tmp.dir, "old.txt"), join(tmp.dir, "new.txt"));
    const head = await commitAll(tmp.dir, "rename");
    assert.deepEqual((await changedPaths(base, head, tmp.dir)).sort(), ["new.txt", "old.txt"]);
    assert.equal(await hasCommit(base, tmp.dir), true);
    assert.equal(await hasCommit("0000000000000000000000000000000000000000", tmp.dir), false);
  } finally {
    tmp.cleanup();
  }
});

test("alreadyExists is GitHub's 422 already_exists and nothing else", () => {
  const refused = (status: number, data: unknown) =>
    new RequestError("refused", status, {
      request: { method: "POST", url: "https://api.github.com/x", headers: {} },
      response: { status, url: "https://api.github.com/x", headers: {}, data },
    });
  assert.equal(alreadyExists(refused(422, { errors: [{ resource: "Release", code: "already_exists", field: "tag_name" }] })), true);
  assert.equal(alreadyExists(refused(422, { errors: [{ code: "invalid", field: "tag_name" }] })), false);
  assert.equal(alreadyExists(refused(422, { message: "Validation Failed" })), false);
  assert.equal(alreadyExists(refused(500, { errors: [{ code: "already_exists" }] })), false);
  assert.equal(alreadyExists(new Error("boom")), false);
});

test("splitRepository takes owner/name and nothing else", () => {
  assert.deepEqual(splitRepository("o/r"), { owner: "o", repo: "r" });
  for (const bad of ["o", "o/", "/r", "o/r/x", ""]) {
    assert.throws(() => splitRepository(bad), /owner\/name/, bad);
  }
});
