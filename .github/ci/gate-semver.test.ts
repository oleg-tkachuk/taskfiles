import assert from "node:assert/strict";
import { test } from "node:test";

import { isReleaseTag } from "./gate-semver.ts";

const cases: [string, boolean][] = [
  ["v1.2.3", true],
  ["v10.0.0", true],
  ["v1.2.3-rc.1", true],
  ["v1.2.3+build.5", true],
  ["1.2.3", false],
  ["v1.2", false],
  ["v01.2.3", false],
  ["v1.2.3x", false],
  ["v1abc.2.3", false],
  ["vv1.2.3", false],
];
for (const [tag, want] of cases) {
  test(`${tag} is${want ? "" : " not"} a release tag`, () => assert.equal(isReleaseTag(tag), want));
}
