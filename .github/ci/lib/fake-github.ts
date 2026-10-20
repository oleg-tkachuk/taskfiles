// An in-memory GitHub for tests: it records what a command asked for.

import type { GitHub } from "./github.ts";

// FakeData is the repository the fake answers from, and what was asked of it.
export interface FakeData {
  tags: Set<string>;
  releases: Set<string>;
  dispatched: { eventType: string; payload: Record<string, string> }[];
  workflowRuns: { workflow: string; ref: string; inputs: Record<string, string> }[];
}

// fakeData is an empty repository.
export function fakeData(): FakeData {
  return { tags: new Set(), releases: new Set(), dispatched: [], workflowRuns: [] };
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
    async createRelease(tag) {
      data.releases.add(tag);
    },
  };
}
