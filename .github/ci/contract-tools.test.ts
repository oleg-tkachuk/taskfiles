import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { TOOLS, install, wrapper } from "./contract-tools.ts";
import { tempDir } from "./lib/temp-dir.ts";

// VERSIONS pins every tool, as ci.yml does.
const VERSIONS = { TRIVY_VERSION: "0.1.0", HADOLINT_VERSION: "v2.0.0", GITLEAKS_VERSION: "v8.0.0", CHECKOV_VERSION: "3.0.0" };

test("a wrapper runs the pinned image as the runner's user, in the working directory, with its own entrypoint", () => {
  const checkov = TOOLS.find((tool) => tool.name === "checkov");
  assert.ok(checkov);
  const script = wrapper(checkov, "3.0.0");
  assert.match(script, /^#!\/bin\/sh\n/);
  assert.match(script, /--user "\$\(id -u\):\$\(id -g\)"/);
  assert.match(script, /-v "\$PWD:\$PWD" -w "\$PWD"/);
  assert.match(script, / --entrypoint checkov bridgecrew\/checkov:3\.0\.0 "\$@"\n$/);
});

test("install writes an executable wrapper per tool at the version pinned for it", () => {
  const tmp = tempDir();
  try {
    const paths = install(tmp.dir, VERSIONS);
    assert.deepEqual(
      paths.map((path) => path.slice(tmp.dir.length + 1)),
      TOOLS.map((tool) => tool.name),
    );
    for (const tool of TOOLS) {
      const path = join(tmp.dir, tool.name);
      assert.equal(statSync(path).mode & 0o111, 0o111, `${tool.name} is executable`);
      const version = VERSIONS[tool.versionEnv as keyof typeof VERSIONS];
      assert.ok(readFileSync(path, "utf8").includes(`${tool.image}:${version} "$@"`), `${tool.name} runs ${version}`);
    }
  } finally {
    tmp.cleanup();
  }
});

test("install refuses a tool with no pinned version", () => {
  const tmp = tempDir();
  try {
    assert.throws(() => install(tmp.dir, { ...VERSIONS, GITLEAKS_VERSION: "" }), /GITLEAKS_VERSION is not set/);
  } finally {
    tmp.cleanup();
  }
});
