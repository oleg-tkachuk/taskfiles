import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { parse } from "yaml";

import {
  BREAKING_LABEL,
  CATEGORY_LABELS,
  IMPACT_HEADING,
  LABEL_BY_TYPE,
  categoryOf,
  consumerImpact,
  impactSection,
  isBreaking,
  missingLabels,
  type Commit,
  type PullRequest,
} from "./release-notes.ts";

// GITHUB_DIR holds the two files that have to spell what this module spells.
const GITHUB_DIR = join(import.meta.dirname, "..", "..");

function commit(subject: string, body = ""): Commit {
  return { sha: subject, subject, body };
}

function pull(body: string, labels: string[] = []): PullRequest {
  return { number: 7, title: "feat(go): add a gate", body, labels };
}

test("a breaking change is a `!` after the type or scope, or a BREAKING CHANGE footer", () => {
  assert.equal(isBreaking(commit("feat!: drop a task")), true);
  assert.equal(isBreaking(commit("feat(k8s)!: take the backlog as LOG_TAIL")), true);
  assert.equal(isBreaking(commit("refactor: split", "why\n\nBREAKING CHANGE: service is gone")), true);
  assert.equal(isBreaking(commit("refactor: split", "BREAKING-CHANGE: service is gone")), true);
  assert.equal(isBreaking(commit("feat(go): add a gate")), false);
  assert.equal(isBreaking(commit("fix: say why it broke!")), false);
  assert.equal(isBreaking(commit("docs: mention a BREAKING CHANGE: in prose", "no footer here")), false);
});

test("a pull request's category is its strongest commit's", () => {
  assert.equal(categoryOf([commit("ci(lint): fix"), commit("feat(tasklib): add"), commit("docs(readme): say")]), "enhancement");
  assert.equal(categoryOf([commit("docs: say"), commit("fix(go): fail")]), "bug");
  assert.equal(categoryOf([commit("perf(release): skip")]), "bug");
  assert.equal(categoryOf([commit("docs(readme): say")]), "documentation");
});

test("commits that release nothing, or follow no convention, have no category", () => {
  assert.equal(categoryOf([commit("ci(actions): update"), commit("chore: tidy"), commit("refactor: move")]), undefined);
  assert.equal(categoryOf([commit("Merge branch 'main'"), commit("Feat: capitalised")]), undefined);
  assert.equal(categoryOf([]), undefined);
});

test("an unlabelled pull request gets its category, and the breaking mark when it breaks", () => {
  assert.deepEqual(missingLabels({ pull: pull(""), commits: [commit("feat(go): add")] }), ["enhancement"]);
  assert.deepEqual(missingLabels({ pull: pull(""), commits: [commit("feat(go)!: rename")] }), [BREAKING_LABEL, "enhancement"]);
  assert.deepEqual(missingLabels({ pull: pull(""), commits: [commit("ci: update")] }), []);
});

test("a category chosen by hand is left alone, but not a missing breaking mark", () => {
  assert.deepEqual(missingLabels({ pull: pull("", ["bug"]), commits: [commit("feat(go): add")] }), []);
  assert.deepEqual(missingLabels({ pull: pull("", ["bug"]), commits: [commit("fix(go)!: refuse")] }), [BREAKING_LABEL]);
  assert.deepEqual(missingLabels({ pull: pull("", [BREAKING_LABEL, "enhancement"]), commits: [commit("feat!: drop")] }), []);
});

test("the consumer impact is the text under its heading, up to the next one", () => {
  const body = "## What and why\n\nA gate.\n\n## Consumer impact\n\n<!-- say what changes -->\n`go:lint` now needs v2.\n\nSet `X`.\n\n## Checklist\n\n- [x] lint";
  assert.equal(consumerImpact(body), "`go:lint` now needs v2.\n\nSet `X`.");
  assert.equal(consumerImpact("## consumer impact  \r\nlast section\r\n"), "last section");
});

test("no section, an empty one, or one that says none is no impact", () => {
  assert.equal(consumerImpact("## What and why\n\nA gate."), undefined);
  assert.equal(consumerImpact("## Consumer impact\n\n<!-- instructions -->\n\n## Checklist"), undefined);
  for (const none of ["None", "none.", "N/A", "Nothing"]) {
    assert.equal(consumerImpact(`## Consumer impact\n\n${none}\n`), undefined, none);
  }
  assert.equal(consumerImpact("### Consumer impact\n\nnot the section\n"), undefined);
});

test("the notes open with each stated impact under its pull request, and with nothing when none is stated", () => {
  const stated = { number: 3, title: "fix(go): fail on a missing tool", body: "## Consumer impact\n\nInstall gotestsum.", labels: [] };
  const silent = { number: 4, title: "ci: update", body: "## Consumer impact\n\nNone", labels: [] };
  assert.equal(impactSection([stated, silent]), "## Consumer impact\n\n**fix(go): fail on a missing tool** (#3)\n\nInstall gotestsum.\n\n");
  assert.equal(impactSection([silent]), "");
});

test("every label this module adds is a category of .github/release.yml, the breaking one first", () => {
  const config = parse(readFileSync(join(GITHUB_DIR, "release.yml"), "utf8")) as { changelog: { categories: { labels: string[] }[] } };
  const categories = config.changelog.categories.map((category) => category.labels);
  assert.deepEqual(categories[0], [BREAKING_LABEL]);
  for (const label of [...Object.values(LABEL_BY_TYPE), ...CATEGORY_LABELS]) {
    assert.ok(categories.some((labels) => labels.includes(label)), `${label} is in no category`);
  }
});

test("the pull request template carries the section, and unfilled it states no impact", () => {
  const template = readFileSync(join(GITHUB_DIR, "PULL_REQUEST_TEMPLATE.md"), "utf8");
  assert.ok(template.includes(`## ${IMPACT_HEADING}\n`), "the template has no Consumer impact section");
  assert.equal(consumerImpact(template), undefined);
});
