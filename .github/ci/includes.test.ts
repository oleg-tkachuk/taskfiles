// The consumers' include lists name modules that are there: a module renamed
// or moved would otherwise fail only in CI, on two operating systems.
import assert from "node:assert/strict";
import { existsSync, globSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { INCLUDES as CONSUMABLE, remoteTasklib } from "./consumable-include.ts";
import { INCLUDES as SMOKE } from "./smoke-setup-consumer.ts";

const repoRoot = new URL("../../", import.meta.url);

for (const [name, includes] of [["consumer-smoke", SMOKE], ["consumable", CONSUMABLE]] as const) {
  test(`${name} includes only modules that exist`, () => {
    for (const module of Object.values(includes)) {
      assert.ok(existsSync(new URL(`${module}/Taskfile.yaml`, repoRoot)), module);
    }
  });
}

// NOT_MODULES are the directories that hold a Taskfile and are not a module:
// the demo is a consumer of the library, and node_modules is nobody's.
const NOT_MODULES = ["demo", "node_modules"];

test("consumer-smoke includes every module there is", () => {
  const root = fileURLToPath(repoRoot);
  const onDisk = globSync(["*/Taskfile.yaml", "*/*/Taskfile.yaml"], { cwd: root })
    .map((file) => dirname(file).split("\\").join("/"))
    .filter((module) => !NOT_MODULES.includes(module.split("/")[0] ?? ""))
    .sort();
  assert.deepEqual([...Object.values(SMOKE)].sort(), onDisk);
});

test("the remote include names the repository and the tag", () => {
  assert.equal(remoteTasklib("o/r", "v1.2.3"), "https://github.com/o/r.git//%s?ref=v1.2.3");
});
