// A command run the way a workflow step runs it, for tests: its own process,
// the environment the step sets, and the outputs it leaves for later steps.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { OUTPUT_FILE } from "./actions.ts";
import { capture } from "./exec.ts";
import { tempDir } from "./temp-dir.ts";

// CI_DIR is where the commands live, beside this directory.
const CI_DIR = join(import.meta.dirname, "..");
// INHERITED are the variables a command needs from the machine to start git
// and node; nothing else of the test's environment reaches it.
const INHERITED = ["PATH", "HOME"];

// CommandRun is how a command ended: its exit code, what it logged, and the
// outputs it set.
export interface CommandRun {
  code: number;
  stdout: string;
  outputs: Record<string, string>;
}

// runCommand runs the command in CI_DIR named command with args, in cwd, with
// env as the step's environment.
export async function runCommand(command: string, options: { args?: readonly string[]; cwd?: string; env?: Record<string, string> } = {}): Promise<CommandRun> {
  const tmp = tempDir();
  try {
    const outputFile = join(tmp.dir, OUTPUT_FILE);
    const env: NodeJS.ProcessEnv = { [OUTPUT_FILE]: outputFile, ...options.env };
    for (const name of INHERITED) {
      env[name] = process.env[name];
    }
    const result = await capture(process.execPath, [join(CI_DIR, command), ...(options.args ?? [])], { cwd: options.cwd, env });
    return { code: result.code, stdout: result.stdout, outputs: existsSync(outputFile) ? parseOutputs(readFileSync(outputFile, "utf8")) : {} };
  } finally {
    tmp.cleanup();
  }
}

// parseOutputs reads the name=value lines setOutput writes.
function parseOutputs(text: string): Record<string, string> {
  return Object.fromEntries(
    text
      .split("\n")
      .filter((line) => line !== "")
      .map((line) => {
        const at = line.indexOf("=");
        return [line.slice(0, at), line.slice(at + 1)];
      }),
  );
}
