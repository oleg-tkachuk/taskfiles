// Verify: python passes each source dir and the typecheck module as data.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-python.ts
//
// uv as the representative of the python family; a shim records every call.
// PY_SRC lists two directories that must arrive as two arguments, PY carries
// a command substitution that used to run in doctor, and TYPECHECK_MODULE
// must reach Python as an argument rather than as code.

import { mkdirSync, writeFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";
import { join } from "node:path";

import { runMain } from "./lib/main.ts";
import { SUBSTITUTION, calls, expect, expectNotSubstituted, modulePath, passed, shim, task, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// SOURCES and MODULE are what PY_SRC and TYPECHECK_MODULE carry.
const SOURCES = ["src", "tests"];
const MODULE = "mypy";
// PROBE_SCRIPT and ABSENT are python/uv's probe for the typecheck module and
// the exit code it means "not installed" by — _UV_TC_ABSENT there.
const PROBE_SCRIPT = "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else int(sys.argv[2]))";
const ABSENT = "3";
// PROJECT_FILES are what the module looks for to call a directory a project.
const PROJECT_FILES = ["pyproject.toml", "uv.lock"];

async function main(): Promise<void> {
  const { dir, bin } = workspace("pythongate");
  const record = join(dir, "calls.json");
  shim(bin, "uv", { replies: { "--version": "uv 0.13.0\n" }, record });
  for (const source of SOURCES) {
    mkdirSync(join(dir, source), { recursive: true });
  }
  for (const file of PROJECT_FILES) {
    writeFileSync(join(dir, file), "");
  }
  writeTaskfile(dir, { py: { taskfile: modulePath("python/uv"), vars: { PY_SRC: SOURCES.join(" "), TYPECHECK_MODULE: MODULE } } });
  const options = { cwd: dir, path: [bin] };

  await task(["py:doctor", `PY=py${SUBSTITUTION}`], options);
  expectNotSubstituted(dir, "PY");

  await taskOk(["py:typecheck"], options);
  const seen = calls(record);
  const called = (argv: readonly string[]) => seen.some((call) => isDeepStrictEqual(call, argv));
  expect(called(["run", "python", "-c", PROBE_SCRIPT, MODULE, ABSENT]), "the typecheck module did not arrive as an argument", seen);
  expect(called(["run", MODULE, ...SOURCES]), "PY_SRC did not arrive as one argument per directory", seen);
  passed("python passes each source dir and the typecheck module as data");
}

if (import.meta.main) {
  await runMain(main);
}
