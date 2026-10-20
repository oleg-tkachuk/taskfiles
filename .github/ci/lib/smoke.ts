// What every consumer-smoke check repeats: a directory of its own under the
// runner's temp, shims standing in for the tools a module calls, a Taskfile
// including one module, and Task run against it.
//
// A shim is a small Node script, so it records its argv as JSON — exactly
// the arguments it got, a space or a quote in one included — rather than as
// lines a later grep has to match.

import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { delimiter, join } from "node:path";

import { info } from "./actions.ts";
import { TASKFILE } from "./consumer.ts";
import { requireEnv } from "./env.ts";
import { capture, type Captured } from "./exec.ts";

// LIBRARY_CHECKOUT is where consumer-smoke checks the library out, under the
// workspace.
export const LIBRARY_CHECKOUT = "taskfiles";
// SHIMS_DIR holds a check's shims, under its own directory.
const SHIMS_DIR = "shims";
// EXECUTABLE is the mode a shim is written with.
const EXECUTABLE = 0o755;

// libraryRoot is the library checkout.
export function libraryRoot(): string {
  return join(requireEnv("GITHUB_WORKSPACE"), LIBRARY_CHECKOUT);
}

// modulePath is the Taskfile directory of module in the library checkout.
export function modulePath(module: string): string {
  return join(libraryRoot(), module);
}

// Workspace is a check's own directory and the shims directory in it.
export interface Workspace {
  dir: string;
  bin: string;
}

// workspace makes the directory name under base — the runner's temp unless
// a test says otherwise — with an empty shims directory.
export function workspace(name: string, base: string = requireEnv("RUNNER_TEMP")): Workspace {
  const dir = join(base, name);
  const bin = join(dir, SHIMS_DIR);
  mkdirSync(bin, { recursive: true });
  return { dir, bin };
}

// ShimBehaviour is what a shim does when it is called.
export interface ShimBehaviour {
  // exec runs that program with the shim's arguments and exits as it does,
  // and nothing else here applies: a wrapper rather than a symlink, for a
  // launcher that finds its own directory from the path it was run as.
  exec?: string;
  // record names a file each call's argv is appended to, one JSON array per
  // line; a relative one is relative to where the shim is called.
  record?: string;
  // replies maps a first argument to what the shim prints for it, then
  // exits 0 without recording the call: `--version`, say.
  replies?: Readonly<Record<string, string>>;
  // stdout is printed on every recorded call.
  stdout?: string;
  // stdin "echo" copies the shim's input to its output; "drain" reads and
  // drops it, as a tool reading a password from stdin would.
  stdin?: "echo" | "drain";
  // copy copies one file over another, as a generator writing its output.
  copy?: { from: string; to: string };
}

// SHIM_PROGRAM runs a ShimBehaviour, read from the JSON prepended to it.
// getBuiltinModule rather than require or import: the shim has no extension,
// so whether Node reads it as CommonJS or as a module is not this file's to
// decide.
const SHIM_PROGRAM = `
const fs = process.getBuiltinModule("node:fs");
const args = process.argv.slice(2);
if (behaviour.exec) {
  const { spawnSync } = process.getBuiltinModule("node:child_process");
  let run = spawnSync(behaviour.exec, args, { stdio: "inherit" });
  // A file with no #! line is a shell script to a shell, which runs it
  // with sh when the kernel will not; spawn does not, so this does.
  if (run.error?.code === "ENOEXEC") run = spawnSync("/bin/sh", [behaviour.exec, ...args], { stdio: "inherit" });
  if (run.error) {
    process.stderr.write(\`shim: \${behaviour.exec}: \${run.error.message}\n\`);
    process.exit(1);
  }
  process.exit(run.status ?? 1);
}
if (behaviour.replies && Object.hasOwn(behaviour.replies, args[0] ?? "")) {
  process.stdout.write(behaviour.replies[args[0]]);
  process.exit(0);
}
if (behaviour.record) fs.appendFileSync(behaviour.record, JSON.stringify(args) + "\\n");
if (behaviour.copy) fs.copyFileSync(behaviour.copy.from, behaviour.copy.to);
if (behaviour.stdin) {
  let input = "";
  try { input = fs.readFileSync(0, "utf8"); } catch {}
  if (behaviour.stdin === "echo") process.stdout.write(input);
}
if (behaviour.stdout) process.stdout.write(behaviour.stdout);
`;

// shim writes an executable called name into bin that does what behaviour
// says.
export function shim(bin: string, name: string, behaviour: ShimBehaviour): void {
  mkdirSync(bin, { recursive: true });
  const file = join(bin, name);
  writeFileSync(file, `#!/usr/bin/env node\nconst behaviour = ${JSON.stringify(behaviour)};\n${SHIM_PROGRAM}`);
  chmodSync(file, EXECUTABLE);
}

// calls is every argv recorded in file, oldest first; none when nothing
// called the shim.
export function calls(file: string): string[][] {
  if (!existsSync(file)) {
    return [];
  }
  return readFileSync(file, "utf8")
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => JSON.parse(line) as string[]);
}

// lastCall is the argv of the latest call recorded in file, refusing a shim
// nothing called.
export function lastCall(file: string): string[] {
  const all = calls(file);
  const last = all.at(-1);
  if (last === undefined) {
    throw new Error(`${file}: nothing called the shim`);
  }
  return last;
}

// IncludeSpec is one include of a check's Taskfile: the module's directory
// and the vars it is given.
export interface IncludeSpec {
  taskfile: string;
  vars?: Record<string, unknown>;
}

// writeTaskfile writes a Taskfile into dir including each module under its
// alias. JSON is YAML, and every value goes through JSON.stringify, so a
// path with a quote or a space in it stays one value.
export function writeTaskfile(dir: string, includes: Readonly<Record<string, IncludeSpec>>): void {
  const document = {
    version: "3",
    includes: Object.fromEntries(Object.entries(includes).map(([alias, spec]) => [alias, { taskfile: spec.taskfile, dir: ".", ...(spec.vars === undefined ? {} : { vars: spec.vars }) }])),
    tasks: {},
  };
  writeFileSync(join(dir, TASKFILE), `${JSON.stringify(document, null, 2)}\n`);
}

// TaskOptions is where Task runs, what goes ahead of PATH, and what else it
// is told.
export interface TaskOptions {
  cwd: string;
  path?: readonly string[];
  env?: Readonly<Record<string, string>>;
}

// withPath is the environment with dirs ahead of PATH, and extra over it.
export function withPath(dirs: readonly string[], extra: Readonly<Record<string, string>> = {}): NodeJS.ProcessEnv {
  return { ...process.env, ...extra, PATH: [...dirs, process.env.PATH ?? ""].join(delimiter) };
}

// task runs Task with args and returns how it ended; its output goes to the
// step's log too, so a failure shows what Task said.
export async function task(args: readonly string[], options: TaskOptions): Promise<Captured> {
  const result = await capture("task", args, { cwd: options.cwd, env: withPath(options.path ?? [], options.env) });
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
  return result;
}

// taskOk runs Task and throws when it fails.
export async function taskOk(args: readonly string[], options: TaskOptions): Promise<Captured> {
  const result = await task(args, options);
  if (result.code !== 0) {
    throw new Error(`task ${args.join(" ")} exited with ${result.code}`);
  }
  return result;
}

// taskFails runs Task and throws when it succeeds, naming what it should
// have refused.
export async function taskFails(args: readonly string[], options: TaskOptions, refused: string): Promise<Captured> {
  const result = await task(args, options);
  if (result.code === 0) {
    throw new Error(`task ${args.join(" ")} passed ${refused}`);
  }
  return result;
}

// expect throws message, with the detail that shows why, unless ok holds.
export function expect(ok: boolean, message: string, detail?: unknown): asserts ok {
  if (!ok) {
    throw new Error(detail === undefined ? message : `${message}: ${typeof detail === "string" ? detail : JSON.stringify(detail)}`);
  }
}

// passed logs a check that held.
export function passed(message: string): void {
  info(`✔ ${message}`);
}

// PROBE is the file SUBSTITUTION creates if a shell ever runs it: a value
// carrying SUBSTITUTION must reach the tool as data, and PROBE never appear.
export const PROBE = "substituted";
export const SUBSTITUTION = `$(touch ${PROBE})`;

// expectNotSubstituted throws, naming what carried it, when PROBE is in dir.
export function expectNotSubstituted(dir: string, carrier: string): void {
  expect(!existsSync(join(dir, PROBE)), `a command substitution in ${carrier} ran`);
}

// expectArgs throws unless every one of want is a whole argument of argv.
export function expectArgs(argv: readonly string[], want: readonly string[], what: string): void {
  const missing = want.filter((arg) => !argv.includes(arg));
  expect(missing.length === 0, `${what}: ${missing.join(", ")} did not arrive as one argument each`, argv);
}
