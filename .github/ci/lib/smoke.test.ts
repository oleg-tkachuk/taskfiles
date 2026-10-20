import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { parse } from "yaml";

import { execute } from "./exec.ts";
import { PROBE, calls, expect, expectArgs, expectNotSubstituted, lastCall, shim, workspace, writeTaskfile } from "./smoke.ts";
import { tempDir } from "./temp-dir.ts";

test("a recording shim keeps each argument whole, and answers a reply unrecorded", async () => {
  const tmp = tempDir();
  try {
    const { bin } = workspace("gate", tmp.dir);
    const record = join(tmp.dir, "argv.json");
    shim(bin, "tool", { record, replies: { "--version": "1.0\n" }, stdout: "done\n" });
    assert.equal(await execute(join(bin, "tool"), ["--version"]), "1.0\n");
    assert.equal(await execute(join(bin, "tool"), ["a b", "it's", "$(x)"]), "done\n");
    await execute(join(bin, "tool"), ["second"]);
    assert.deepEqual(calls(record), [["a b", "it's", "$(x)"], ["second"]]);
    assert.deepEqual(lastCall(record), ["second"]);
  } finally {
    tmp.cleanup();
  }
});

test("lastCall refuses a shim nothing called; calls reads it as no calls", () => {
  assert.deepEqual(calls("/nonexistent/argv.json"), []);
  assert.throws(() => lastCall("/nonexistent/argv.json"), /nothing called the shim/);
});

test("a shim copies a file, and echoes its input", async () => {
  const tmp = tempDir();
  try {
    const from = tmp.write("from", "generated\n");
    const to = join(tmp.dir, "to");
    shim(tmp.dir, "gen", { copy: { from, to } });
    shim(tmp.dir, "cat", { stdin: "echo" });
    await execute(join(tmp.dir, "gen"), []);
    assert.equal(readFileSync(to, "utf8"), "generated\n");
    const { spawnSync } = await import("node:child_process");
    assert.equal(spawnSync(join(tmp.dir, "cat"), { input: "piped" }).stdout.toString(), "piped");
  } finally {
    tmp.cleanup();
  }
});

test("an exec shim runs its target with its arguments and exits as it does — a script with no #! line included", async () => {
  const tmp = tempDir();
  try {
    const target = tmp.write("target", 'printf "%s|" "$@"\nexit 3\n');
    const { chmodSync } = await import("node:fs");
    chmodSync(target, 0o755);
    shim(tmp.dir, "wrapper", { exec: target });
    const { spawnSync } = await import("node:child_process");
    const run = spawnSync(join(tmp.dir, "wrapper"), ["a b", "c"]);
    assert.equal(run.stdout.toString(), "a b|c|");
    assert.equal(run.status, 3);
  } finally {
    tmp.cleanup();
  }
});

test("writeTaskfile writes a Taskfile whose values survive quotes and spaces", () => {
  const tmp = tempDir();
  try {
    writeTaskfile(tmp.dir, { m: { taskfile: "/lib/it's here", vars: { FLAGS: "--a --b", LIST: ["x"] } }, n: { taskfile: "/lib/n" } });
    const doc = parse(readFileSync(join(tmp.dir, "Taskfile.yaml"), "utf8")) as { includes: Record<string, unknown> };
    assert.deepEqual(doc.includes, {
      m: { taskfile: "/lib/it's here", dir: ".", vars: { FLAGS: "--a --b", LIST: ["x"] } },
      n: { taskfile: "/lib/n", dir: "." },
    });
  } finally {
    tmp.cleanup();
  }
});

test("expect, expectArgs and expectNotSubstituted throw what failed", () => {
  assert.doesNotThrow(() => expect(true, "never"));
  assert.throws(() => expect(false, "it broke", ["a"]), /it broke: \["a"\]/);
  assert.doesNotThrow(() => expectArgs(["x", "my ns"], ["my ns"], "helm"));
  assert.throws(() => expectArgs(["my", "ns"], ["my ns"], "helm"), /helm: my ns did not arrive/);
  const tmp = tempDir();
  try {
    assert.doesNotThrow(() => expectNotSubstituted(tmp.dir, "X"));
    writeFileSync(join(tmp.dir, PROBE), "");
    assert.throws(() => expectNotSubstituted(tmp.dir, "X"), /substitution in X ran/);
  } finally {
    tmp.cleanup();
  }
});
