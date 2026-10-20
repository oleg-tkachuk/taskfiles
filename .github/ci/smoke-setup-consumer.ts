// Setup: a consumer that includes the library.
//
// Usage: node smoke-setup-consumer.ts, from the workspace holding the library
// checkout; the consumer is built beside it.
//
// It holds a Go module, so the tasks that compile and generate have something
// to act on. Loading a module proves it parses; running one is the only thing
// that proves it works.

import { writeFileSync } from "node:fs";
import { join } from "node:path";

import { CONSUMER_DIR, consumerTaskfile, seedConsumer, type Includes } from "./lib/consumer.ts";
import { commitAll } from "./lib/git.ts";
import { runMain } from "./lib/main.ts";
import { LIBRARY_CHECKOUT, passed } from "./lib/smoke.ts";

// INCLUDES is every module, side by side: a module quietly claiming a name
// another one uses shows up as the consumer failing to load.
export const INCLUDES: Includes = {
  release: "release",
  k8s: "k8s",
  go: "go",
  python: "python/poetry",
  pythonuv: "python/uv",
  node: "node",
  pnpm: "pnpm",
  compose: "compose",
  security: "security",
  checkov: "checkov",
  monorepo: "monorepo",
  argocd: "argocd",
  auth: "auth",
  codegen: "codegen",
  cosign: "cosign",
  helm: "helm",
  sealedsecrets: "sealed-secrets",
  local: "runtime/orbstack",
  localdocker: "runtime/docker",
  localk3d: "runtime/k3d",
  localkind: "runtime/kind",
  localminikube: "runtime/minikube",
};

// LOCAL_TASKLIB includes each module from the checkout beside the consumer.
const LOCAL_TASKLIB = `../${LIBRARY_CHECKOUT}/%s`;

// GO_FIXTURE is the Go module the consumer holds: a package with a test, and
// a go:generate directive codegen:generate must honour.
export const GO_FIXTURE: Readonly<Record<string, string>> = {
  "go.mod": "module example.com/smoke\n\ngo 1.21\n",
  "smoke.go": String.raw`package smoke

//go:generate sh -c "printf 'package smoke\n\nconst Generated = true\n' > generated.go"

// Greeting is what the fixture's test asserts on.
func Greeting() string { return "hi" }
`,
  "smoke_test.go": `package smoke

import "testing"

func TestGreeting(t *testing.T) {
	if Greeting() != "hi" {
		t.Fatal("unexpected greeting")
	}
}
`,
};

async function main(): Promise<void> {
  const dir = join(process.cwd(), CONSUMER_DIR);
  await seedConsumer(dir, consumerTaskfile(LOCAL_TASKLIB, INCLUDES));
  for (const [file, content] of Object.entries(GO_FIXTURE)) {
    writeFileSync(join(dir, file), content);
  }
  await commitAll(dir, "chore: fixture");
  passed(`a consumer including ${Object.keys(INCLUDES).length} modules is in ${dir}`);
}

if (import.meta.main) {
  await runMain(main);
}
