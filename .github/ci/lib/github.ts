// The GitHub API calls the workflows make, through Octokit.
//
// Octokit's default plugins retry a transient failure and wait out a rate
// limit, so one 5xx does not lose a release.

import { Octokit, RequestError } from "octokit";

import type { PullRequest } from "./release-notes.ts";

// NOT_FOUND is the status GitHub answers for a release or ref that is not
// there.
const NOT_FOUND = 404;
// UNPROCESSABLE is the status GitHub answers for a request it validated and
// refused.
const UNPROCESSABLE = 422;
// ALREADY_EXISTS is the validation code GitHub gives a second release for one
// tag.
const ALREADY_EXISTS = "already_exists";

// GitHub is what a command asks of the repository it runs for.
export interface GitHub {
  // dispatch sends a repository_dispatch event of eventType with payload.
  dispatch(eventType: string, payload: Record<string, string>): Promise<void>;
  // runWorkflow starts workflow on ref with inputs.
  runWorkflow(workflow: string, ref: string, inputs: Record<string, string>): Promise<void>;
  // tagExists reports whether the repository holds tag.
  tagExists(tag: string): Promise<boolean>;
  // releaseExists reports whether a release is published for tag.
  releaseExists(tag: string): Promise<boolean>;
  // pullRequestsFor lists the merged pull requests that brought commit sha.
  pullRequestsFor(sha: string): Promise<PullRequest[]>;
  // addLabels puts labels on pull request number, creating any the
  // repository does not have yet.
  addLabels(number: number, labels: string[]): Promise<void>;
  // generateNotes is the notes GitHub writes for tag from the pull requests
  // merged since previous — or since the release before it, when undefined.
  generateNotes(tag: string, previous: string | undefined): Promise<string>;
  // createRelease publishes a release for tag with notes as its body. It is
  // false when tag already has a release.
  createRelease(tag: string, notes: string): Promise<boolean>;
}

// splitRepository is owner and name of an owner/name repository.
export function splitRepository(repository: string): { owner: string; repo: string } {
  const [owner, repo, ...rest] = repository.split("/");
  if (owner === undefined || owner === "" || repo === undefined || repo === "" || rest.length > 0) {
    throw new Error(`${repository} is not an owner/name repository`);
  }
  return { owner, repo };
}

// found turns a 404 into false and passes any other failure on.
async function found(request: Promise<unknown>): Promise<boolean> {
  try {
    await request;
    return true;
  } catch (err) {
    if (err instanceof RequestError && err.status === NOT_FOUND) {
      return false;
    }
    throw err;
  }
}

// alreadyExists reports whether err is GitHub refusing to create something
// that is already there.
export function alreadyExists(err: unknown): boolean {
  if (!(err instanceof RequestError) || err.status !== UNPROCESSABLE) {
    return false;
  }
  const data = err.response?.data as { errors?: { code?: string }[] } | undefined;
  return data?.errors?.some((e) => e.code === ALREADY_EXISTS) ?? false;
}

// gitHubFor is the real API for repository, authenticated with token.
export function gitHubFor(token: string, repository: string): GitHub {
  const octokit = new Octokit({ auth: token });
  const where = splitRepository(repository);
  return {
    async dispatch(eventType, payload) {
      await octokit.rest.repos.createDispatchEvent({ ...where, event_type: eventType, client_payload: payload });
    },
    async runWorkflow(workflow, ref, inputs) {
      await octokit.rest.actions.createWorkflowDispatch({ ...where, workflow_id: workflow, ref, inputs });
    },
    tagExists: (tag) => found(octokit.rest.git.getRef({ ...where, ref: `tags/${tag}` })),
    releaseExists: (tag) => found(octokit.rest.repos.getReleaseByTag({ ...where, tag })),
    async pullRequestsFor(sha) {
      const { data } = await octokit.rest.repos.listPullRequestsAssociatedWithCommit({ ...where, commit_sha: sha });
      return data
        .filter((pull) => pull.merged_at !== null)
        .map((pull) => ({ number: pull.number, title: pull.title, body: pull.body ?? "", labels: pull.labels.map((label) => label.name) }));
    },
    async addLabels(number, labels) {
      await octokit.rest.issues.addLabels({ ...where, issue_number: number, labels });
    },
    async generateNotes(tag, previous) {
      const { data } = await octokit.rest.repos.generateReleaseNotes({
        ...where,
        tag_name: tag,
        ...(previous === undefined ? {} : { previous_tag_name: previous }),
      });
      return data.body;
    },
    async createRelease(tag, notes) {
      try {
        await octokit.rest.repos.createRelease({ ...where, tag_name: tag, name: tag, body: notes });
        return true;
      } catch (err) {
        if (alreadyExists(err)) {
          return false;
        }
        throw err;
      }
    },
  };
}
