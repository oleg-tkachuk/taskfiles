// Setup: the tools `task contracts` runs the gates against, at the versions
// ci.yml pins.
//
// Usage: RUNNER_TEMP=… GITHUB_PATH=… TRIVY_VERSION=… HADOLINT_VERSION=…
//        GITLEAKS_VERSION=… CHECKOV_VERSION=… KIND_VERSION=…
//        KUBECTL_VERSION=… node contract-tools.ts
//
// Each scanner is its official image behind a wrapper on PATH, so a version
// is one pin in the workflow that Renovate moves, and the bump's pull request
// runs the contracts at the new version before it can merge itself. The
// wrapper runs as the runner's user, so what a tool writes into the tree is
// not left root-owned, and mounts the working directory at its own path,
// because the modules pass paths relative to it.
//
// kind and kubectl are binaries instead: kind creates a cluster on the host's
// docker, and kubectl talks to it on a host port. Each is downloaded from its
// project's own release location and checked against the sha256 published
// beside it. Not an action: this repository runs only its own, GitHub's, and
// a short allowlist, and helm/kind-action is not on it.

import { createHash } from "node:crypto";
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

// Binary is one downloaded tool: where its release puts the executable and
// the sha256 beside it, for a version and a CPU architecture.
export interface Binary {
  name: string;
  versionEnv: string;
  url(version: string, arch: string): string;
  checksumUrl(version: string, arch: string): string;
}

// BINARIES are the cluster and the client the k8s contract uses.
export const BINARIES: readonly Binary[] = [
  {
    name: "kind",
    versionEnv: "KIND_VERSION",
    url: (v, a) => `https://github.com/kubernetes-sigs/kind/releases/download/${v}/kind-linux-${a}`,
    checksumUrl: (v, a) => `https://github.com/kubernetes-sigs/kind/releases/download/${v}/kind-linux-${a}.sha256sum`,
  },
  {
    name: "kubectl",
    versionEnv: "KUBECTL_VERSION",
    url: (v, a) => `https://dl.k8s.io/release/${v}/bin/linux/${a}/kubectl`,
    checksumUrl: (v, a) => `https://dl.k8s.io/release/${v}/bin/linux/${a}/kubectl.sha256`,
  },
];

// ARCHES maps Node's name for the CPU to the one the releases use.
const ARCHES: Record<string, string> = { x64: "amd64", arm64: "arm64" };
// SHA256_HEX is a sha256 digest as the checksum files write it.
const SHA256_HEX = /^[0-9a-f]{64}$/;

// releaseArch is the release name for arch, or an error for one with none.
export function releaseArch(arch: string): string {
  const name = ARCHES[arch];
  if (name === undefined) {
    throw new Error(`no kind or kubectl release for the ${arch} architecture`);
  }
  return name;
}

// expectedDigest reads a checksum file: the digest alone, as kubectl's is, or
// the digest then the file name, as kind's is.
export function expectedDigest(text: string): string {
  const digest = text.trim().split(/\s+/)[0] ?? "";
  if (!SHA256_HEX.test(digest)) {
    throw new Error(`not a sha256 checksum file: ${JSON.stringify(text.slice(0, 80))}`);
  }
  return digest;
}

// Fetcher downloads a URL, failing on anything but success.
export type Fetcher = (url: string) => Promise<Buffer>;

// fetchBytes is the real download.
async function fetchBytes(url: string): Promise<Buffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${url}: ${response.status} ${response.statusText}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

// installBinary downloads binary at version for arch into dir, refusing it
// unless its sha256 matches the one published beside it.
export async function installBinary(dir: string, binary: Binary, version: string, arch: string, get: Fetcher): Promise<string> {
  const want = expectedDigest((await get(binary.checksumUrl(version, arch))).toString("utf8"));
  const bytes = await get(binary.url(version, arch));
  const got = createHash("sha256").update(bytes).digest("hex");
  if (got !== want) {
    throw new Error(`${binary.name} ${version}: sha256 ${got}, expected ${want}`);
  }
  mkdirSync(dir, { recursive: true });
  const path = join(dir, binary.name);
  writeFileSync(path, bytes);
  chmodSync(path, EXECUTABLE);
  return path;
}

async function main(): Promise<void> {
  const dir = join(requireEnv("RUNNER_TEMP"), TOOLS_DIR);
  for (const path of install(dir, process.env)) {
    info(`✔ ${path}`);
  }
  const arch = releaseArch(process.arch);
  for (const binary of BINARIES) {
    info(`✔ ${await installBinary(dir, binary, requireEnv(binary.versionEnv), arch, fetchBytes)}`);
  }
  appendFileSync(requireEnv("GITHUB_PATH"), `${dir}\n`);
}

if (import.meta.main) {
  await runMain(main);
}
