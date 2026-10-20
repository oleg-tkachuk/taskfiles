// Verify: proto:check derives what it watches, and refuses when it cannot.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-codegen-proto-check.ts
//
// No buf here. A shim stands in for the generator and writes whatever
// canonical.go holds — the stub's "source" — over the generated file, which
// lets the gate's own behaviours be exercised: the derivation, drift, a
// regenerated change not committed yet, an unparseable template, and a target
// with nothing committed under it.

import { copyFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { commitAll, git, initRepo } from "./lib/git.ts";
import { runMain } from "./lib/main.ts";
import { expect, modulePath, passed, shim, task, taskFails, taskOk, workspace, writeTaskfile, type TaskOptions } from "./lib/smoke.ts";

// TEMPLATE is the buf template; OUT_DIR and STUB, where it says to generate.
const TEMPLATE = "buf.gen.yaml";
const OUT_DIR = "gen/go";
const STUB = `${OUT_DIR}/greet.pb.go`;
// SOURCE stands for the proto: what the shim generates the stub from.
const SOURCE = "canonical.go";
// PACKAGE is the stub as committed; DRIFTED, one generation would rewrite.
const PACKAGE = "package greetv1\n";
const DRIFTED = "package greetv1\n// drifted\n";
// templateFor is a template generating into out.
const templateFor = (out: string) => `version: v2\nplugins:\n  - local: protoc-gen-go\n    out: ${out}\n`;
// GLOB_SPEC is a pathspec with magic, whose parenthesis a shell reads as
// syntax unless each pathspec is quoted.
const GLOB_SPEC = ":(glob)gen/**";

// What the gate says, by outcome.
const FRESH = "stubs match their sources";
const STALE = "stubs are stale";

async function main(): Promise<void> {
  const { dir, bin } = workspace("protogate");
  const at = (path: string) => join(dir, path);
  mkdirSync(at(OUT_DIR), { recursive: true });
  shim(bin, "buf", { copy: { from: at(SOURCE), to: at(STUB) } });
  await initRepo(dir);
  writeFileSync(at(TEMPLATE), templateFor(OUT_DIR));
  writeFileSync(at(SOURCE), PACKAGE);
  copyFileSync(at(SOURCE), at(STUB));
  writeTaskfile(dir, { cg: { taskfile: modulePath("codegen"), vars: { PROJECT_NAME: "gate", BUF_TEMPLATE: [TEMPLATE] } } });
  await commitAll(dir, "seed");
  const options: TaskOptions = { cwd: dir, path: [bin] };
  const restore = (path: string) => git(["checkout", "--quiet", "--", path], dir);
  const expectFresh = async (args: string[], what: string) => {
    const out = await taskOk(["cg:proto:check", ...args], options);
    expect(out.stdout.includes(FRESH), `proto:check did not report ${what} as fresh`, out.stdout);
  };
  const expectRefused = async (args: string[], refused: string, says: string) => {
    const out = await taskFails(["cg:proto:check", ...args], options, refused);
    expect(`${out.stdout}${out.stderr}`.includes(says), `proto:check failed, but did not say "${says}"`, out.stderr);
  };

  await expectFresh([], "a tree whose stubs are committed");
  passed("proto:check passes on a tree whose stubs are committed");

  await expectFresh([`PROTO_PATHSPEC=${GLOB_SPEC}`], "a glob pathspec over committed stubs");
  writeFileSync(at(STUB), DRIFTED);
  await expectRefused([`PROTO_PATHSPEC=${GLOB_SPEC}`], "a stale stub under a glob pathspec", STALE);
  await restore(OUT_DIR);
  passed("proto:check takes a pathspec with magic, and still sees drift through it");

  // A quote in the pathspec is data: the gate reports the directory it
  // cannot find instead of failing to parse the value.
  await expectRefused(["PROTO_PATHSPEC=gen/it's"], "a pathspec that names nothing", "gen/it's holds no tracked file");
  passed("proto:check reads a quote in its pathspec as data");

  // An out: path is read from a file, so it is data too.
  const probe = at("substituted");
  writeFileSync(at(TEMPLATE), templateFor(`gen/$(touch ${probe})`));
  await task(["cg:proto:check"], options);
  expect(!existsSync(probe), "proto:check ran a command substitution from an out: path");
  await restore(TEMPLATE);
  passed("proto:check never runs a command substitution from an out: path");

  writeFileSync(at(STUB), DRIFTED);
  await expectRefused([], "a stale stub", STALE);
  await restore(OUT_DIR);
  passed("proto:check fails when a stub no longer matches what generation writes");

  // A source change regenerated but not yet committed is a fresh tree: the
  // gate runs before a commit, so it must pass here.
  writeFileSync(at(SOURCE), "package greetv1\n// v2\n");
  await taskOk(["cg:proto"], options);
  await expectFresh([], "a regenerated, uncommitted change");
  passed("proto:check passes a regenerated, uncommitted change");

  writeFileSync(at(SOURCE), "package greetv1\n// v3\n");
  await expectRefused([], "a source change it was not regenerated for", STALE);
  writeFileSync(at(SOURCE), PACKAGE);
  await restore(OUT_DIR);
  passed("proto:check fails a source change that was not regenerated");

  // out: inside a flow mapping is valid YAML buf accepts, and invisible to a
  // line parser. The gate must refuse, not report a clean tree.
  writeFileSync(at(TEMPLATE), `version: v2\nplugins: [{local: protoc-gen-go, out: ${OUT_DIR}}]\n`);
  await expectRefused([], "a template it could not parse", "no out: path in");
  passed("proto:check refuses a template whose out: it cannot read");

  // out: . is legitimate, and watching the root would report every unrelated
  // change as a stale stub.
  writeFileSync(at(TEMPLATE), templateFor("."));
  await expectRefused([], "a template writing to the component root", "writes to the component root");
  passed("proto:check refuses a template that writes to the component root");

  await restore(TEMPLATE);
  await expectRefused(["PROTO_PATHSPEC=gen/nothing"], "with nothing tracked to check", "checks nothing");
  passed("proto:check refuses when no watched directory holds a tracked file");
}

if (import.meta.main) {
  await runMain(main);
}
