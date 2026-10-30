import assert from "node:assert/strict";
import { test } from "node:test";

import { HOW_TO_SET_IT, TOKEN_VAR, requireToken } from "./renovate-require-token.ts";

test("a set token passes", () => {
  assert.doesNotThrow(() => requireToken("a-token"));
});

test("a missing token fails naming the secret", () => {
  assert.throws(() => requireToken(undefined), new RegExp(`${TOKEN_VAR} secret is not set`));
});

// A permission missing here fails the run without failing the workflow, so
// the list is pinned rather than read back from the text it checks.
test("the failure names every permission Renovate writes with", () => {
  for (const permission of ["Contents", "Pull requests", "Issues", "Workflows", "Commit statuses"]) {
    assert.match(HOW_TO_SET_IT, new RegExp(`^  ${permission} +read and write`, "m"));
  }
});

test("the failure says how to set it", () => {
  assert.match(HOW_TO_SET_IT, /gh secret set RENOVATE_TOKEN --env renovate/);
});
