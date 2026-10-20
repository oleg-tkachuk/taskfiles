// Verify: gosec runs the module's own tool before one on PATH.
//
// Usage: RUNNER_TEMP=… GITHUB_WORKSPACE=… node smoke-security-gosec.ts, on a
// machine with Go and no gosec of its own on PATH.
//
// A gosec built outside the module carries gosec's own x/tools, which can be
// too old for the export data the module's Go writes. So a module pinning
// gosec with a `tool` directive gets that one even with another on PATH; a
// module without one falls back to PATH; with neither the task fails naming
// `go get -tool`. The tool is a local stand-in that records its argv, so
// nothing is fetched.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { isDeepStrictEqual } from "node:util";

import { runMain } from "./lib/main.ts";
import { expect, lastCall, modulePath, passed, shim, taskFails, taskOk, workspace, writeTaskfile } from "./lib/smoke.ts";

// TOOL_ARGV is the file the stand-in tool writes, in the module it runs in;
// PATH_ARGV, the one the PATH shim records to.
const TOOL_ARGV = "argv";
const PATH_ARGV = "argv.json";
// GOSEC_FLAGS is what the module passes; ARGS, every argument gosec gets.
const GOSEC_FLAGS = "-quiet";
const ARGS = [GOSEC_FLAGS, "./..."];
// INSTALL_HINT is what the task names when there is no gosec at all.
const INSTALL_HINT = "go get -tool github.com/securego/gosec/v2/cmd/gosec";

// FILES are the stand-in gosec, a module pinning it as a tool, and a module
// with no tool of its own.
const FILES: Readonly<Record<string, string>> = {
  "fake/go.mod": "module example.com/fake\n\ngo 1.24\n",
  "fake/cmd/gosec/main.go": `package main

import (
	"os"
	"strings"
)

func main() { _ = os.WriteFile("${TOOL_ARGV}", []byte("tool "+strings.Join(os.Args[1:], " ")), 0o644) }
`,
  "withtool/go.mod": "module example.com/withtool\n\ngo 1.24\n\nrequire example.com/fake v0.0.0\n\nreplace example.com/fake => ../fake\n\ntool example.com/fake/cmd/gosec\n",
  "plain/go.mod": "module example.com/plain\n\ngo 1.24\n",
};

async function main(): Promise<void> {
  const { dir, bin } = workspace("gosec-tool");
  for (const [path, content] of Object.entries(FILES)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), content);
  }
  shim(bin, "gosec", { record: PATH_ARGV });
  writeTaskfile(dir, { sec: { taskfile: modulePath("security"), vars: { GO_MODULES: ["withtool", "plain"], GOSEC_FLAGS } } });

  await taskOk(["sec:gosec"], { cwd: dir, path: [bin] });
  const tool = join(dir, "withtool", TOOL_ARGV);
  expect(existsSync(tool) && readFileSync(tool, "utf8") === `tool ${ARGS.join(" ")}`, "the module's tool was not used");
  expect(!existsSync(join(dir, "withtool", PATH_ARGV)), "the PATH gosec ran in a module that pins its own");
  const fallback = lastCall(join(dir, "plain", PATH_ARGV));
  expect(isDeepStrictEqual(fallback, ARGS), "the PATH gosec was not the fallback", fallback);

  const missing = await taskFails(["sec:gosec"], { cwd: dir, env: { NO_COLOR: "1" } }, "with no gosec for a module to run");
  expect(missing.stderr.includes(INSTALL_HINT), "the task did not name go get -tool", missing.stderr);
  passed("gosec prefers the module's tool, falls back to PATH, and names go get -tool");
}

if (import.meta.main) {
  await runMain(main);
}
