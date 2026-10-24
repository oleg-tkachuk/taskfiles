import assert from "node:assert/strict";
import { test } from "node:test";

import { fakeData, fakeGitHub } from "./lib/fake-github.ts";
import { publish } from "./publish-release.ts";

test("publishes a release for a tag that exists", async () => {
  const data = fakeData();
  data.tags.add("v1.0.0");
  await publish(fakeGitHub(data), "v1.0.0");
  assert.deepEqual([...data.releases], ["v1.0.0"]);
});

test("leaves a release that is already there", async () => {
  const data = fakeData();
  data.releases.add("v1.0.0");
  await publish(fakeGitHub(data), "v1.0.0");
  assert.deepEqual([...data.releases], ["v1.0.0"]);
});

test("a release another run published after the check is left as it is", async () => {
  const data = fakeData();
  data.tags.add("v1.0.0");
  data.releases.add("v1.0.0");
  // The other run published between this one's check and its create.
  const github = { ...fakeGitHub(data), releaseExists: async () => false };
  await publish(github, "v1.0.0");
  assert.deepEqual([...data.releases], ["v1.0.0"]);
});

test("refuses a tag that is not in the repository rather than creating it", async () => {
  const data = fakeData();
  await assert.rejects(publish(fakeGitHub(data), "v9.9.9"), /not in the repository/);
  assert.equal(data.releases.size, 0);
});
