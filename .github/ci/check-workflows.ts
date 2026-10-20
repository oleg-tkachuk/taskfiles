// Report a workflow step whose script lives in the YAML rather than in
// .github/ci, a CI command nothing runs, and a step running one that is not
// there.
//
// Usage: node check-workflows.ts [repository root]   (exit 1 on a finding)
//
// A script inside YAML is type-checked by nothing, cannot be run locally, and
// is the one place zizmor has to guess at what reaches the shell. One-command
// steps stay inline; anything longer is a command in .github/ci a step runs.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

import { parse } from "yaml";

import { info } from "./lib/actions.ts";
import { runMain } from "./lib/main.ts";

// Where each kind of file lives, under the repository root.
export const WORKFLOWS_DIR = ".github/workflows";
export const ACTIONS_DIR = ".github/actions";
export const CI_DIR = ".github/ci";
// ACTION_FILE is a composite action's definition, in its own directory.
const ACTION_FILE = "action.yml";
// TASKFILE runs the commands the workflows do not: the lint ones.
const TASKFILE = "Taskfile.yaml";
// COMMAND_SUFFIX ends a command; TEST_SUFFIX, a test, which no step runs.
const COMMAND_SUFFIX = ".ts";
const TEST_SUFFIX = ".test.ts";
// COMMAND_REF is how a step names a command: its path from the CI directory.
const COMMAND_REF = /\.github\/ci\/([A-Za-z0-9._-]+\.ts)/g;
// WORKFLOW_SUFFIXES are the extensions Actions reads a workflow from.
const WORKFLOW_SUFFIXES = [".yml", ".yaml"];

// Run is one step's run: and the file it is in.
export interface Run {
  file: string;
  run: string;
}

interface Step {
  run?: unknown;
}

// stepsOf is every step of a workflow or composite action document.
function stepsOf(document: unknown): Step[] {
  if (typeof document !== "object" || document === null) {
    return [];
  }
  const doc = document as { jobs?: Record<string, { steps?: Step[] }>; runs?: { steps?: Step[] } };
  return [...Object.values(doc.jobs ?? {}).flatMap((job) => job.steps ?? []), ...(doc.runs?.steps ?? [])];
}

// runsIn is every run: of every step in files, read relative to root.
export function runsIn(root: string, files: readonly string[]): Run[] {
  return files.flatMap((file) =>
    stepsOf(parse(readFileSync(join(root, file), "utf8")))
      .filter((step): step is { run: string } => typeof step.run === "string")
      .map((step) => ({ file, run: step.run })),
  );
}

// isMultiLine reports whether run holds more than one line once its
// trailing newlines are gone: a block scalar holding one command is one.
export function isMultiLine(run: string): boolean {
  return run.replace(/\n+$/, "").includes("\n");
}

// commandRefs is every command a text names.
export function commandRefs(text: string): string[] {
  return [...text.matchAll(COMMAND_REF)].map((match) => match[1] ?? "");
}

// workflowFiles and actionFiles are the files the runner reads steps from.
function workflowFiles(root: string): string[] {
  const dir = join(root, WORKFLOWS_DIR);
  return existsSync(dir) ? readdirSync(dir).filter((name) => WORKFLOW_SUFFIXES.some((suffix) => name.endsWith(suffix))).map((name) => join(WORKFLOWS_DIR, name)) : [];
}

function actionFiles(root: string): string[] {
  const dir = join(root, ACTIONS_DIR);
  if (!existsSync(dir)) {
    return [];
  }
  return readdirSync(dir)
    .map((name) => join(ACTIONS_DIR, name, ACTION_FILE))
    .filter((file) => existsSync(join(root, file)));
}

// commands is every command in the CI directory: its top-level .ts files,
// tests aside.
function commands(root: string): string[] {
  return readdirSync(join(root, CI_DIR)).filter((name) => name.endsWith(COMMAND_SUFFIX) && !name.endsWith(TEST_SUFFIX));
}

// findings is everything wrong with the workflows and commands under root.
export function findings(root: string): string[] {
  const runs = runsIn(root, [...workflowFiles(root), ...actionFiles(root)]);
  const found: string[] = [];
  for (const { file, run } of runs) {
    if (isMultiLine(run)) {
      found.push(`${file}: a multi-line run: belongs in ${CI_DIR}/: ${run.split("\n")[0]}`);
    }
  }
  const taskfile = join(root, TASKFILE);
  const sources = [...runs.map((r) => r.run), existsSync(taskfile) ? readFileSync(taskfile, "utf8") : ""];
  const referenced = new Set(sources.flatMap(commandRefs));
  const present = new Set(commands(root));
  for (const command of present) {
    if (!referenced.has(command)) {
      found.push(`${join(CI_DIR, command)}: no workflow step or task runs it`);
    }
  }
  for (const command of referenced) {
    if (!present.has(command)) {
      found.push(`${join(CI_DIR, command)}: a step runs it, and it is not there`);
    }
  }
  return found;
}

async function main(): Promise<void> {
  const root = process.argv[2] ?? ".";
  const found = findings(root);
  for (const finding of found) {
    info(finding);
  }
  if (found.length > 0) {
    throw new Error(`${found.length} finding(s) in the workflows under ${relative(process.cwd(), root) || "."}`);
  }
}

if (import.meta.main) {
  await runMain(main);
}
