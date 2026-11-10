import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";

import { fakeData, fakeGitHub, generatedNotes } from "./lib/fake-github.ts";
import { commitAll, git, initRepo } from "./lib/git.ts";
import { tempDir } from "./lib/temp-dir.ts";
import { historyOf, publish, type History } from "./publish-release.ts";

// NO_HISTORY is a release with nothing to read: the cases that never reach
// the notes.
const NO_HISTORY: History = { previous: undefined, commits: [] };

test("publishes a release for a tag that exists", async () => {
  const data = fakeData();
  data.tags.add("v1.0.0");
  await publish(fakeGitHub(data), "v1.0.0", NO_HISTORY);
  assert.deepEqual([...data.releases], ["v1.0.0"]);
  assert.equal(data.notes.get("v1.0.0"), generatedNotes("v1.0.0", undefined));
});

test("leaves a release that is already there", async () => {
  const data = fakeData();
  data.releases.add("v1.0.0");
  await publish(fakeGitHub(data), "v1.0.0", NO_HISTORY);
  assert.deepEqual([...data.releases], ["v1.0.0"]);
  assert.equal(data.labelled.length, 0);
});

test("a release another run published after the check is left as it is", async (t) => {
  const data = fakeData();
  data.tags.add("v1.0.0");
  data.releases.add("v1.0.0");
  // The other run published between this one's check and its create.
  const github = { ...fakeGitHub(data), releaseExists: async () => false };
  const log = t.mock.method(console, "log", () => {});
  await publish(github, "v1.0.0", NO_HISTORY);
  assert.deepEqual([...data.releases], ["v1.0.0"]);
  assert.equal(log.mock.calls.at(-1)?.arguments[0], "✔ release v1.0.0 already exists");
});

test("refuses a tag that is not in the repository rather than creating it", async () => {
  const data = fakeData();
  await assert.rejects(publish(fakeGitHub(data), "v9.9.9", NO_HISTORY), /not in the repository/);
  assert.equal(data.releases.size, 0);
});

test("labels each pull request from its commits and opens the notes with the stated impact", async (t) => {
  t.mock.method(console, "log", () => {});
  const data = fakeData();
  data.tags.add("v1.1.0");
  const feature = { number: 5, title: "feat(go): add a gate", body: "## Consumer impact\n\nInstall the tool.", labels: [] };
  const upkeep = { number: 6, title: "ci: update", body: "", labels: [] };
  data.pulls.set("a", [feature]);
  data.pulls.set("b", [feature]);
  data.pulls.set("c", [upkeep]);
  const history: History = {
    previous: "v1.0.0",
    commits: [
      { sha: "a", subject: "ci(lint): fix the gate", body: "" },
      { sha: "b", subject: "feat(go)!: add a gate", body: "" },
      { sha: "c", subject: "ci(actions): update", body: "" },
      { sha: "d", subject: "chore: pushed without a pull request", body: "" },
    ],
  };
  await publish(fakeGitHub(data), "v1.1.0", history);
  assert.deepEqual(data.labelled, [{ number: 5, labels: ["breaking", "enhancement"] }]);
  assert.equal(
    data.notes.get("v1.1.0"),
    `## Consumer impact\n\n**feat(go): add a gate** (#5)\n\nInstall the tool.\n\n${generatedNotes("v1.1.0", "v1.0.0")}`,
  );
});

test("a failure reading or labelling the pull requests still publishes, with GitHub's notes alone", async (t) => {
  const log = t.mock.method(console, "log", () => {});
  const data = fakeData();
  data.tags.add("v1.1.0");
  const github = {
    ...fakeGitHub(data),
    pullRequestsFor: async () => {
      throw new Error("Resource not accessible by integration");
    },
  };
  await publish(github, "v1.1.0", { previous: "v1.0.0", commits: [{ sha: "a", subject: "feat: add", body: "" }] });
  assert.equal(data.notes.get("v1.1.0"), generatedNotes("v1.1.0", "v1.0.0"));
  const logged = log.mock.calls.map((call) => String(call.arguments[0]));
  assert.ok(
    logged.some((line) => line.startsWith("::warning::") && line.includes("Resource not accessible")),
    logged.join("\n"),
  );
});

test("a tag's history is the commits since the release before it, oldest first", async () => {
  const tmp = tempDir();
  try {
    const repo = join(tmp.dir, "repo");
    await initRepo(repo);
    tmp.write("repo/a", "1\n");
    await commitAll(repo, "feat: first");
    await git(["tag", "v1.0.0"], repo);
    assert.deepEqual((await historyOf("v1.0.0", repo)).previous, undefined);
    assert.deepEqual(
      (await historyOf("v1.0.0", repo)).commits.map((commit) => commit.subject),
      ["feat: first"],
    );

    tmp.write("repo/b", "2\n");
    const second = await commitAll(repo, "fix(go): second\n\nwhy it broke\n\nBREAKING CHANGE: a task is gone");
    tmp.write("repo/c", "3\n");
    await commitAll(repo, "docs: third");
    await git(["tag", "not-a-release"], repo);
    await git(["tag", "v1.1.0"], repo);

    const history = await historyOf("v1.1.0", repo);
    assert.equal(history.previous, "v1.0.0");
    assert.deepEqual(
      history.commits.map((commit) => commit.subject),
      ["fix(go): second", "docs: third"],
    );
    assert.deepEqual(history.commits[0], { sha: second, subject: "fix(go): second", body: "why it broke\n\nBREAKING CHANGE: a task is gone" });
  } finally {
    tmp.cleanup();
  }
});
