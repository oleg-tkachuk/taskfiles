// Setup: the tools `task contracts` runs the gates against, at the versions
// ci.yml pins.
//
// Usage: RUNNER_TEMP=… GITHUB_PATH=… TRIVY_VERSION=… HADOLINT_VERSION=…
//        GITLEAKS_VERSION=… CHECKOV_VERSION=… node contract-tools.ts
//
// Each tool is its official image behind a wrapper on PATH, so a version is
// one pin in the workflow that Renovate moves, and the bump's pull request
// runs the contracts at the new version before it can merge itself. The
// wrapper runs as the runner's user, so what a tool writes into the tree is
// not left root-owned, and mounts the working directory at its own path,
// because the modules pass paths relative to it.

import { appendFileSync, chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { info } from "./lib/actions.ts";
import { requireEnv } from "./lib/env.ts";
import { runMain } from "./lib/main.ts";

// Tool is one wrapped tool: the command name the modules call, its image, the
// entrypoint that runs it there, and the variable holding its pinned version.
export interface Tool {
  name: string;
  image: string;
  entrypoint: string;
  versionEnv: string;
}

// TOOLS are the tools the contracts call. checkov's image entrypoint is the
// GitHub Action wrapper and hadolint's image has none, so each is named.
export const TOOLS: readonly Tool[] = [
  { name: "trivy", image: "aquasec/trivy", entrypoint: "trivy", versionEnv: "TRIVY_VERSION" },
  { name: "hadolint", image: "hadolint/hadolint", entrypoint: "/bin/hadolint", versionEnv: "HADOLINT_VERSION" },
  { name: "gitleaks", image: "zricethezav/gitleaks", entrypoint: "gitleaks", versionEnv: "GITLEAKS_VERSION" },
  { name: "checkov", image: "bridgecrew/checkov", entrypoint: "checkov", versionEnv: "CHECKOV_VERSION" },
];

// TOOLS_DIR is where the wrappers go, under RUNNER_TEMP.
const TOOLS_DIR = "contract-tools";
// EXECUTABLE is the mode a wrapper needs to be found on PATH and run.
const EXECUTABLE = 0o755;

// wrapper is the script that runs tool at version in place of the binary.
export function wrapper(tool: Tool, version: string): string {
  return [
    "#!/bin/sh",
    // HOME: the image's own is not writable by the runner's user, and trivy
    // keeps its cache there.
    `exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:$PWD" -w "$PWD" --entrypoint ${tool.entrypoint} ${tool.image}:${version} "$@"`,
    "",
  ].join("\n");
}

// install writes a wrapper for every tool into dir, each at the version env
// names for it, and returns their paths. A tool with no version is refused:
// an unpinned image is whatever the registry serves today.
export function install(dir: string, env: Record<string, string | undefined>): string[] {
  mkdirSync(dir, { recursive: true });
  return TOOLS.map((tool) => {
    const version = env[tool.versionEnv];
    if (version === undefined || version === "") {
      throw new Error(`${tool.versionEnv} is not set — every contract tool is pinned in ci.yml`);
    }
    const path = join(dir, tool.name);
    writeFileSync(path, wrapper(tool, version));
    chmodSync(path, EXECUTABLE);
    return path;
  });
}

async function main(): Promise<void> {
  const dir = join(requireEnv("RUNNER_TEMP"), TOOLS_DIR);
  for (const path of install(dir, process.env)) {
    info(`✔ ${path}`);
  }
  appendFileSync(requireEnv("GITHUB_PATH"), `${dir}\n`);
}

if (import.meta.main) {
  await runMain(main);
}
