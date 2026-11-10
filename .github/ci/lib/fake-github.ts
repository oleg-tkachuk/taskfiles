// An in-memory GitHub for tests: it records what a command asked for.

import type { GitHub } from "./github.ts";
import type { PullRequest } from "./release-notes.ts";

// FakeData is the repository the fake answers from, and what was asked of it.
export interface FakeData {
  tags: Set<string>;
  releases: Set<string>;
  // The body each release was published with.
  notes: Map<string, string>;
  // The merged pull requests behind each commit.
  pulls: Map<string, PullRequest[]>;
  labelled: { number: number; labels: string[] }[];
  dispatched: { eventType: string; payload: Record<string, string> }[];
  workflowRuns: { workflow: string; ref: string; inputs: Record<string, string> }[];
}

// fakeData is an empty repository.
export function fakeData(): FakeData {
  return { tags: new Set(), releases: new Set(), notes: new Map(), pulls: new Map(), labelled: [], dispatched: [], workflowRuns: [] };
}

// generatedNotes stands in for the notes GitHub writes: it names the range
// they were asked for.
export function generatedNotes(tag: string, previous: string | undefined): string {
  return `## What's Changed\n${previous ?? "the beginning"}...${tag}\n`;
}

// fakeGitHub answers from data and records into it.
export function fakeGitHub(data: FakeData): GitHub {
  return {
    async dispatch(eventType, payload) {
      data.dispatched.push({ eventType, payload });
    },
    async runWorkflow(workflow, ref, inputs) {
      data.workflowRuns.push({ workflow, ref, inputs });
    },
    tagExists: async (tag) => data.tags.has(tag),
    releaseExists: async (tag) => data.releases.has(tag),
    pullRequestsFor: async (sha) => data.pulls.get(sha) ?? [],
    async addLabels(number, labels) {
      data.labelled.push({ number, labels });
    },
    generateNotes: async (tag, previous) => generatedNotes(tag, previous),
    async createRelease(tag, notes) {
      // As GitHub does: a second release for one tag is refused.
      if (data.releases.has(tag)) {
        return false;
      }
      data.releases.add(tag);
      data.notes.set(tag, notes);
      return true;
    },
  };
}
