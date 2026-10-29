import assert from "node:assert/strict";
import { test } from "node:test";

import { CI_DIR, WORKFLOWS_DIR, ACTIONS_DIR, commandRefs, findings, isMultiLine } from "./check-workflows.ts";
import { runCommand } from "./lib/command.ts";
import { tempDir } from "./lib/temp-dir.ts";

// fixture is a repository with workflow ci.yml and commands in the CI dir.
function fixture(workflow: string, commands: string[], extra: Record<string, string> = {}) {
  const tmp = tempDir();
  tmp.write(`${WORKFLOWS_DIR}/ci.yml`, workflow);
  tmp.write(`${CI_DIR}/lib/helper.ts`, "");
  for (const command of commands) {
    tmp.write(`${CI_DIR}/${command}`, "");
  }
  for (const [path, content] of Object.entries(extra)) {
    tmp.write(path, content);
  }
  return tmp;
}

const cases: [string, "clean" | "reported", string, string[], Record<string, string>?][] = [
  ["one command and a CI command", "clean", "jobs:\n  a:\n    steps:\n      - run: task lint\n      - run: node .github/ci/smoke.ts\n", ["smoke.ts"]],
  ["a command under a subdirectory checkout", "clean", 'jobs:\n  a:\n    steps:\n      - run: node "$GITHUB_WORKSPACE/ci/.github/ci/smoke.ts"\n', ["smoke.ts"]],
  ["a multi-line run", "reported", "jobs:\n  a:\n    steps:\n      - run: |\n          set -eu\n          echo hi\n", []],
  ["a block scalar holding one command", "clean", "jobs:\n  a:\n    steps:\n      - run: |\n          echo hi\n", []],
  ["an escaped newline inside one command", "clean", 'jobs:\n  a:\n    steps:\n      - run: printf "%s\\n" done\n', []],
  ["a command nothing runs", "reported", "jobs:\n  a:\n    steps:\n      - run: task lint\n", ["orphan.ts"]],
  ["a step running a missing command", "reported", "jobs:\n  a:\n    steps:\n      - run: node .github/ci/gone.ts\n", []],
  ["a test beside the commands", "clean", "jobs:\n  a:\n    steps:\n      - run: task lint\n", ["x.test.ts"]],
  ["a command a composite action runs", "clean", "jobs: {}\n", ["install.ts"], { [`${ACTIONS_DIR}/setup/action.yml`]: "runs:\n  using: composite\n  steps:\n    - run: node \"$CHECKOUT/.github/ci/install.ts\"\n      shell: bash\n" }],
  ["a multi-line run in a composite action", "reported", "jobs: {}\n", [], { [`${ACTIONS_DIR}/setup/action.yml`]: "runs:\n  using: composite\n  steps:\n    - run: |\n        a\n        b\n      shell: bash\n" }],
  ["a command the Taskfile runs", "clean", "jobs: {}\n", ["lint-only.ts"], { "Taskfile.yaml": "tasks:\n  x:\n    cmds:\n      - node .github/ci/lint-only.ts .\n" }],
  ["an empty workflow file", "clean", "", []],
];
for (const [name, want, workflow, commands, extra] of cases) {
  test(name, () => {
    const tmp = fixture(workflow, commands, extra);
    try {
      const found = findings(tmp.dir);
      assert.equal(found.length > 0 ? "reported" : "clean", want, found.join("\n"));
    } finally {
      tmp.cleanup();
    }
  });
}

test("a multi-line run is named by its first line", () => {
  const tmp = fixture("jobs:\n  a:\n    steps:\n      - run: |\n          set -eu\n          echo hi\n", []);
  try {
    assert.deepEqual(findings(tmp.dir), [`${WORKFLOWS_DIR}/ci.yml: a multi-line run: belongs in ${CI_DIR}/: set -eu`]);
  } finally {
    tmp.cleanup();
  }
});

test("isMultiLine ignores trailing newlines", () => {
  assert.equal(isMultiLine("echo hi\n\n"), false);
  assert.equal(isMultiLine("a\nb"), true);
});

test("commandRefs finds each command a text names", () => {
  assert.deepEqual(commandRefs('node .github/ci/a.ts && node "$X/.github/ci/b-c.ts"'), ["a.ts", "b-c.ts"]);
});

test("the command fails on a finding, naming each, and passes a clean tree", async () => {
  const clean = fixture("jobs:\n  a:\n    steps:\n      - run: node .github/ci/smoke.ts\n", ["smoke.ts"]);
  const broken = fixture("jobs:\n  a:\n    steps:\n      - run: task lint\n", ["orphan.ts"]);
  try {
    assert.equal((await runCommand("check-workflows.ts", { args: [clean.dir] })).code, 0);

    // With no root named, the command checks the directory it runs in.
    const run = await runCommand("check-workflows.ts", { cwd: broken.dir });
    assert.equal(run.code, 1);
    assert.ok(run.stdout.includes(`${CI_DIR}/orphan.ts: no workflow step or task runs it`), run.stdout);
    assert.match(run.stdout, /::error::1 finding\(s\) in the workflows under \.$/m);
  } finally {
    clean.cleanup();
    broken.cleanup();
  }
});
