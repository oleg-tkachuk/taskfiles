// git, run as an argument vector: no shell ever sees a ref or a path.

import { execute } from "./exec.ts";

// A git hook runs `task lint` with GIT_DIR, GIT_INDEX_FILE and friends
// pointing at this repository. Inherited, they make every git call in a
// fixture act on the real repository instead of the fixture's: a `git init`
// there rewrites its config. git itself lists which variables those are.
let isolated: Promise<NodeJS.ProcessEnv> | undefined;

function isolatedEnv(): Promise<NodeJS.ProcessEnv> {
  isolated ??= execute("git", ["rev-parse", "--local-env-vars"]).then((names) => {
    const env = { ...process.env };
    for (const name of lines(names)) {
      delete env[name];
    }
    return env;
  });
  return isolated;
}

// git runs git with args in cwd and returns its standard output.
export async function git(args: readonly string[], cwd?: string): Promise<string> {
  return execute("git", args, { cwd, env: await isolatedEnv() });
}

// lines splits output into its non-empty lines.
export function lines(output: string): string[] {
  return output.split("\n").filter((line) => line !== "");
}

// hasCommit reports whether this clone holds the commit rev names.
export async function hasCommit(rev: string, cwd?: string): Promise<boolean> {
  try {
    await git(["cat-file", "-e", `${rev}^{commit}`], cwd);
    return true;
  } catch {
    return false;
  }
}

// changedPaths lists the paths that differ between from and to. A rename is
// listed by both its paths: moving a file away from its place changes what
// reads it there as surely as deleting it does.
export async function changedPaths(from: string, to: string, cwd?: string): Promise<string[]> {
  return lines(await git(["diff", "--name-only", "--no-renames", from, to], cwd));
}

// AUTHOR signs the commits a fixture repository makes; nothing outside that
// repository sees it.
const AUTHOR = ["-c", "user.name=CI", "-c", "user.email=ci@example.invalid"];

// initRepo makes dir a repository on main.
export async function initRepo(dir: string): Promise<void> {
  await git(["init", "--quiet", "--initial-branch=main", dir]);
}

// commitAll commits everything in dir, as the fixture author, and returns
// the new commit.
export async function commitAll(dir: string, message: string): Promise<string> {
  await git(["add", "--all"], dir);
  await git([...AUTHOR, "commit", "--quiet", "--allow-empty", "-m", message], dir);
  return (await git(["rev-parse", "HEAD"], dir)).trim();
}
