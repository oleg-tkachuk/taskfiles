import assert from "node:assert/strict";
import { test } from "node:test";

import { runCommand } from "./lib/command.ts";
import { OUTPUT, newlyTicked } from "./renovate-tick.ts";

const aOpen = " - [ ] <!-- approve-branch=renovate/a -->chore(deps): update a";
const aDone = " - [x] <!-- approve-branch=renovate/a -->chore(deps): update a";
const bOpen = " - [ ] <!-- approve-branch=renovate/b -->chore(deps): update b";
const bDone = " - [x] <!-- approve-branch=renovate/b -->chore(deps): update b";
const allDone = "- [x] <!-- create-all-awaiting-schedule-prs -->Create all awaiting schedule PRs at once";
const allOpen = allDone.replace("[x]", "[ ]");
const body = (...lines: string[]) => lines.join("\n");

const cases: [string, boolean, string, string][] = [
  ["a box ticked", true, body(aOpen, bOpen), body(aOpen, bDone)],
  ["a top-level box ticked", true, allOpen, allDone],
  ["ticked and reordered", true, body(aOpen, bOpen), body(bDone, aOpen)],
  ["Renovate unticks", false, body(aDone, bOpen), body(aOpen, bOpen)],
  ["Renovate reorders", false, body(aDone, bOpen), body(bOpen, aDone)],
  ["no change", false, aOpen, aOpen],
  ["a box without a marker", false, "- [ ] a note", "- [x] a note"],
  ["empty before and after", false, "", ""],
  ["a ticked box removed", false, aDone, ""],
  ["a second copy of a ticked box", true, aDone, body(aDone, aDone)],
  ["CRLF line endings", true, body(aOpen, bOpen).replaceAll("\n", "\r\n"), body(aOpen, bDone).replaceAll("\n", "\r\n")],
];
for (const [name, want, before, after] of cases) {
  test(name, () => assert.equal(newlyTicked(before, after).length > 0, want));
}

test("names the boxes that were ticked", () => {
  assert.deepEqual(newlyTicked(body(aOpen, bOpen), body(aDone, bDone)), [aDone, bDone]);
});

test("the command proceeds on a new tick and names it, and otherwise says there is nothing to do", async () => {
  const ticked = await runCommand("renovate-tick.ts", { env: { BODY_BEFORE: aOpen, BODY_AFTER: aDone } });
  assert.equal(ticked.code, 0);
  assert.deepEqual(ticked.outputs, { [OUTPUT]: "true" });
  assert.ok(ticked.stdout.includes(`newly ticked:\n${aDone}`), ticked.stdout);

  const untouched = await runCommand("renovate-tick.ts");
  assert.deepEqual(untouched.outputs, { [OUTPUT]: "false" });
  assert.match(untouched.stdout, /no Renovate checkbox was newly ticked — nothing to do/);
});
