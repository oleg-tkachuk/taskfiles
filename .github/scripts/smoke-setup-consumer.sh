#!/usr/bin/env bash
# Setup: a consumer that includes the library
set -euo pipefail
mkdir -p consumer && cd consumer
git init -q
git config user.email ci@example.invalid
git config user.name CI
echo placeholder > README.md
git add -A && git commit -qm "chore: seed"

cat > Taskfile.yaml <<'YAML'
version: "3"
silent: true
vars:
  TASKLIB: '../taskfiles/%s'
  PROJECT_NAME: smoke
  IMAGE_NAMESPACE: acme
  K8S_NAMESPACE: smoke-ns
  REGISTRY: registry.example.com
  VERSION_BASE: 9.9.9
includes:
  release:        { taskfile: '{{printf .TASKLIB "release"}}', dir: . }
  k8s:            { taskfile: '{{printf .TASKLIB "k8s"}}', dir: . }
  go:             { taskfile: '{{printf .TASKLIB "go"}}', dir: . }
  python:         { taskfile: '{{printf .TASKLIB "python/poetry"}}', dir: . }
  pythonuv:       { taskfile: '{{printf .TASKLIB "python/uv"}}', dir: . }
  node:           { taskfile: '{{printf .TASKLIB "node"}}', dir: . }
  pnpm:           { taskfile: '{{printf .TASKLIB "pnpm"}}', dir: . }
  compose:        { taskfile: '{{printf .TASKLIB "compose"}}', dir: . }
  security:       { taskfile: '{{printf .TASKLIB "security"}}', dir: . }
  checkov:        { taskfile: '{{printf .TASKLIB "checkov"}}', dir: . }
  monorepo:       { taskfile: '{{printf .TASKLIB "monorepo"}}', dir: . }
  argocd:         { taskfile: '{{printf .TASKLIB "argocd"}}', dir: . }
  auth:           { taskfile: '{{printf .TASKLIB "auth"}}', dir: . }
  codegen:        { taskfile: '{{printf .TASKLIB "codegen"}}', dir: . }
  cosign:         { taskfile: '{{printf .TASKLIB "cosign"}}', dir: . }
  helm:           { taskfile: '{{printf .TASKLIB "helm"}}', dir: . }
  sealedsecrets:  { taskfile: '{{printf .TASKLIB "sealed-secrets"}}', dir: . }
  local:          { taskfile: '{{printf .TASKLIB "runtime/orbstack"}}', dir: . }
  localdocker:    { taskfile: '{{printf .TASKLIB "runtime/docker"}}', dir: . }
  localk3d:       { taskfile: '{{printf .TASKLIB "runtime/k3d"}}', dir: . }
  localkind:      { taskfile: '{{printf .TASKLIB "runtime/kind"}}', dir: . }
  localminikube:  { taskfile: '{{printf .TASKLIB "runtime/minikube"}}', dir: . }
tasks: {}
YAML

# A module, so the tasks that compile and generate have something to
# act on. Loading a module proves it parses; running one is the only
# thing that proves it works, and the two bugs this job exists to
# catch — a generator whose output is never normalised, a paired skip
# that reports the wrong branch — both parse cleanly.
cat > go.mod <<'GOMOD'
module example.com/smoke

go 1.21
GOMOD

cat > smoke.go <<'GOFILE'
package smoke

//go:generate sh -c "printf 'package smoke\n\nconst Generated = true\n' > generated.go"

// Greeting is what the fixture's test asserts on.
func Greeting() string { return "hi" }
GOFILE

cat > smoke_test.go <<'GOTEST'
package smoke

import "testing"

func TestGreeting(t *testing.T) {
  if Greeting() != "hi" {
    t.Fatal("unexpected greeting")
  }
}
GOTEST

git add -A && git commit -qm "chore: fixture"
