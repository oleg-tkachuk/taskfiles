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

test("refuses a tag that is not in the repository rather than creating it", async () => {
  const data = fakeData();
  await assert.rejects(publish(fakeGitHub(data), "v9.9.9"), /not in the repository/);
  assert.equal(data.releases.size, 0);
});
