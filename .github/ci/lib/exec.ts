// Commands run as an argument vector: no shell ever sees an argument.

import { execFile } from "node:child_process";

// MAX_OUTPUT_BYTES bounds what one command may print: a diff's name list or
// a module's test log is the most any caller reads.
const MAX_OUTPUT_BYTES = 64 * 1024 * 1024;

// ExecOptions is where a command runs and what it is told.
export interface ExecOptions {
  cwd?: string | undefined;
  env?: NodeJS.ProcessEnv | undefined;
}

// Captured is what a finished command left: its exit code and its output.
export interface Captured {
  code: number;
  stdout: string;
  stderr: string;
}

// capture runs file with args and returns how it ended, whether or not it
// succeeded; it throws only when the command could not be started.
export function capture(file: string, args: readonly string[], options: ExecOptions = {}): Promise<Captured> {
  return new Promise((resolve, reject) => {
    execFile(file, [...args], { cwd: options.cwd, env: options.env, maxBuffer: MAX_OUTPUT_BYTES, encoding: "utf8" }, (err, stdout, stderr) => {
      if (err === null) {
        resolve({ code: 0, stdout, stderr });
      } else if (typeof err.code === "number") {
        resolve({ code: err.code, stdout, stderr });
      } else {
        reject(new Error(`${file} could not be run: ${err.message}`, { cause: err }));
      }
    });
  });
}

// execute runs file with args and returns its standard output; it throws,
// with the command's standard error in the message, when it fails.
export async function execute(file: string, args: readonly string[], options: ExecOptions = {}): Promise<string> {
  const result = await capture(file, args, options);
  if (result.code !== 0) {
    const stderr = result.stderr.trim();
    throw new Error(`${file} ${args.join(" ")} exited with ${result.code}${stderr === "" ? "" : `: ${stderr}`}`);
  }
  return result.stdout;
}
