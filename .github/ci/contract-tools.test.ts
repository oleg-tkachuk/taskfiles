import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { BINARIES, TOOLS, expectedDigest, install, installBinary, releaseArch, wrapper } from "./contract-tools.ts";
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

test("a checksum file is read as kubectl writes it and as kind does, and anything else is refused", () => {
  const digest = "a".repeat(64);
  assert.equal(expectedDigest(`${digest}\n`), digest);
  assert.equal(expectedDigest(`${digest}  kind-linux-amd64\n`), digest);
  assert.throws(() => expectedDigest("<html>Not Found</html>"), /not a sha256 checksum file: "<html>/);
  assert.throws(() => expectedDigest(""), /not a sha256 checksum file/);
});

test("the release architecture is the releases' own name, and an unknown one is refused", () => {
  assert.equal(releaseArch("x64"), "amd64");
  assert.equal(releaseArch("arm64"), "arm64");
  assert.throws(() => releaseArch("ia32"), /no kind or kubectl release for the ia32 architecture/);
});

test("installBinary writes an executable whose sha256 matches the published one, and refuses one that does not", async () => {
  const tmp = tempDir();
  try {
    const kind = BINARIES.find((binary) => binary.name === "kind");
    assert.ok(kind);
    const bytes = Buffer.from("#!/bin/sh\necho kind\n");
    const digest = createHash("sha256").update(bytes).digest("hex");
    const served: Record<string, Buffer> = {
      [kind.url("v1.0.0", "amd64")]: bytes,
      [kind.checksumUrl("v1.0.0", "amd64")]: Buffer.from(`${digest}  kind-linux-amd64\n`),
    };
    const get = async (url: string) => {
      const body = served[url];
      if (body === undefined) throw new Error(`unexpected fetch of ${url}`);
      return body;
    };
    const path = await installBinary(tmp.dir, kind, "v1.0.0", "amd64", get);
    assert.deepEqual(readFileSync(path), bytes);
    assert.equal(statSync(path).mode & 0o111, 0o111);

    served[kind.url("v1.0.0", "amd64")] = Buffer.from("tampered\n");
    rmSync(path);
    await assert.rejects(installBinary(tmp.dir, kind, "v1.0.0", "amd64", get), /kind v1\.0\.0: sha256 [0-9a-f]+, expected/);
    assert.equal(existsSync(path), false, "nothing is written when the digest does not match");
  } finally {
    tmp.cleanup();
  }
});

test("the binaries come from their projects' own release locations", () => {
  const urls = BINARIES.map((binary) => binary.url("v1.0.0", "amd64"));
  assert.deepEqual(urls, [
    "https://github.com/kubernetes-sigs/kind/releases/download/v1.0.0/kind-linux-amd64",
    "https://dl.k8s.io/release/v1.0.0/bin/linux/amd64/kubectl",
  ]);
});

test("install refuses a tool with no pinned version", () => {
  const tmp = tempDir();
  try {
    assert.throws(() => install(tmp.dir, { ...VERSIONS, GITLEAKS_VERSION: "" }), /GITLEAKS_VERSION is not set/);
  } finally {
    tmp.cleanup();
  }
});
