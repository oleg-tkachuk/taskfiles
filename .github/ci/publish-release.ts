// Publish: the GitHub release for a tag.
//
// Usage: GH_TOKEN=… GITHUB_REPOSITORY=… TAG=<tag> node publish-release.ts,
// in a clone that holds the tag and the history behind it.
//
// Notes come from merged pull requests since the previous tag — see
// .github/release.yml. Before GitHub writes them, each pull request is
// labelled from its commits, so it lands in the category its changes belong
// to whether or not anyone labelled it; and the notes open with what each one
// says a consumer has to know (lib/release-notes.ts).
//
// A release that already exists is left as it is, so a second run of the
// same verification says so rather than failing. The tag has to exist first:
// creating a release for a missing tag would create the tag too, at the
// default branch's head — a tree nothing verified.

import { info, warning } from "./lib/actions.ts";
import { requireEnv } from "./lib/env.ts";
import { git } from "./lib/git.ts";
import { gitHubFor, type GitHub } from "./lib/github.ts";
import { runMain } from "./lib/main.ts";
import { impactSection, missingLabels, type Commit, type Merged } from "./lib/release-notes.ts";

// History is what a release holds: the commits since the release before it.
export interface History {
  // previous is the tag of the release before, or undefined for the first.
  previous: string | undefined;
  // commits are oldest first.
  commits: Commit[];
}

// TAG_PATTERN is the glob a release tag matches, as release.config.cjs names
// them.
const TAG_PATTERN = "v[0-9]*";
// FIELD and RECORD separate what git log prints: no commit message holds
// either.
const FIELD = "\x1f";
const RECORD = "\x1e";
const LOG_FORMAT = `--format=%H${FIELD}%s${FIELD}%b${RECORD}`;

// historyOf reads tag's history from the clone in cwd.
export async function historyOf(tag: string, cwd?: string): Promise<History> {
  let previous: string | undefined;
  try {
    previous = (await git(["describe", "--tags", "--abbrev=0", "--match", TAG_PATTERN, `${tag}^`], cwd)).trim();
  } catch {
    // No release before this one: the history is everything the tag holds.
    previous = undefined;
  }
  const range = previous === undefined ? tag : `${previous}..${tag}`;
  const log = await git(["log", "--reverse", LOG_FORMAT, range], cwd);
  const commits: Commit[] = [];
  for (const record of log.split(RECORD)) {
    const [sha, subject, body] = record.trim().split(FIELD);
    if (sha !== undefined && sha !== "" && subject !== undefined) {
      commits.push({ sha, subject, body: body ?? "" });
    }
  }
  return { previous, commits };
}

// mergedIn groups commits by the pull request that brought each, in the
// order the pull requests merged. A commit pushed without one belongs to
// none and is left out.
export async function mergedIn(github: GitHub, commits: readonly Commit[]): Promise<Merged[]> {
  const byNumber = new Map<number, Merged>();
  for (const commit of commits) {
    for (const pull of await github.pullRequestsFor(commit.sha)) {
      const merged = byNumber.get(pull.number) ?? { pull, commits: [] };
      merged.commits.push(commit);
      byNumber.set(pull.number, merged);
    }
  }
  return [...byNumber.values()];
}

// notesFor labels the pull requests of history and returns the notes for
// tag. Whatever fails on the way costs the notes that part and not the
// release: a tag that verified must not go unpublished over a label.
export async function notesFor(github: GitHub, tag: string, history: History): Promise<string> {
  let impact = "";
  try {
    const merged = await mergedIn(github, history.commits);
    for (const one of merged) {
      const labels = missingLabels(one);
      if (labels.length > 0) {
        await github.addLabels(one.pull.number, labels);
        info(`✔ #${one.pull.number} labelled ${labels.join(", ")}`);
      }
    }
    impact = impactSection(merged.map((one) => one.pull));
    info(impact === "" ? `○ no pull request in ${tag} states a consumer impact` : `✔ consumer impact collected for ${tag}`);
  } catch (err) {
    warning(`release ${tag}: pull requests not labelled and no consumer impact collected — ${err instanceof Error ? err.message : String(err)}`);
  }
  return impact + (await github.generateNotes(tag, history.previous));
}

// publish creates the release for tag unless it is already there.
export async function publish(github: GitHub, tag: string, history: History): Promise<void> {
  if (await github.releaseExists(tag)) {
    info(`✔ release ${tag} already exists`);
    return;
  }
  if (!(await github.tagExists(tag))) {
    throw new Error(`tag ${tag} is not in the repository; a release for it would create it on the default branch`);
  }
  const notes = await notesFor(github, tag, history);
  // A tag-push run and a dispatched run can both reach this point; the one
  // that loses finds the release there, as a second run of the check would.
  if (!(await github.createRelease(tag, notes))) {
    info(`✔ release ${tag} already exists`);
    return;
  }
  info(`✔ released ${tag}`);
}

async function main(): Promise<void> {
  const tag = requireEnv("TAG");
  await publish(gitHubFor(requireEnv("GH_TOKEN"), requireEnv("GITHUB_REPOSITORY")), tag, await historyOf(tag));
}

if (import.meta.main) {
  await runMain(main);
}
