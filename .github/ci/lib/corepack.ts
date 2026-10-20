// A pnpm standing ahead of corepack's shim, for the pnpm checks.
//
// corepack's own download of a version, run from its cache rather than
// through the shim, is a standalone pnpm without npm installing one.

import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

import { execute } from "./exec.ts";
import { shim } from "./smoke.ts";

// COREPACK_HOME is where corepack keeps its cache and the variable naming it.
export const COREPACK_HOME = "COREPACK_HOME";

// PnpmSetup is the cache corepack used, and the directories holding the
// standalone pnpm and the shim.
export interface PnpmSetup {
  corepackHome: string;
  standalone: string;
  shims: string;
}

// cachedPnpm is where corepack keeps pnpm at version under home.
export function cachedPnpm(home: string, version: string): string {
  return join(home, "v1", "pnpm", version, "pnpm");
}

// setUpPnpm downloads pnpm at version into a corepack cache under dir, puts
// a wrapper running it straight from the cache in dir/standalone, and
// corepack's shim in dir/corepack-shims.
export async function setUpPnpm(dir: string, version: string): Promise<PnpmSetup> {
  const corepackHome = join(dir, "corepack");
  const env = { ...process.env, [COREPACK_HOME]: corepackHome };
  try {
    await execute("corepack", ["--version"], { env });
  } catch {
    throw new Error("this runner's Node ships no corepack");
  }
  await execute("corepack", ["install", "-g", `pnpm@${version}`], { env });
  const cached = cachedPnpm(corepackHome, version);
  if (!existsSync(cached)) {
    throw new Error(`corepack's cache no longer keeps pnpm at ${cached}`);
  }
  const standalone = join(dir, "standalone");
  const shims = join(dir, "corepack-shims");
  shim(standalone, "pnpm", { exec: cached });
  mkdirSync(shims, { recursive: true });
  await execute("corepack", ["enable", "--install-directory", shims, "pnpm"], { env });
  return { corepackHome, standalone, shims };
}
