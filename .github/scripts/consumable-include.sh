#!/usr/bin/env bash
# Verify: the tag includes the way a consumer does
set -euo pipefail
mkdir consumer && cd consumer
git init -q
git config user.email ci@example.invalid
git config user.name CI
echo placeholder > README.md
git add -A && git commit -qm "chore: seed"

cat > Taskfile.yaml <<YAML
version: "3"
silent: true
vars:
  TASKLIB: 'https://github.com/OWNER_REPO.git//%s?ref=TAGVALUE'
  PROJECT_NAME: smoke
  IMAGE_NAMESPACE: acme
  K8S_NAMESPACE: smoke-ns
  REGISTRY: registry.example.com
  VERSION_BASE: 9.9.9
includes:
  release:  { taskfile: '{{printf .TASKLIB "release"}}', dir: . }
  k8s:      { taskfile: '{{printf .TASKLIB "k8s"}}', dir: . }
  go:       { taskfile: '{{printf .TASKLIB "go"}}', dir: . }
  python:   { taskfile: '{{printf .TASKLIB "python/poetry"}}', dir: . }
  node:     { taskfile: '{{printf .TASKLIB "node"}}', dir: . }
  compose:  { taskfile: '{{printf .TASKLIB "compose"}}', dir: . }
  security: { taskfile: '{{printf .TASKLIB "security"}}', dir: . }
  monorepo: { taskfile: '{{printf .TASKLIB "monorepo"}}', dir: . }
  argocd:   { taskfile: '{{printf .TASKLIB "argocd"}}', dir: . }
  auth:     { taskfile: '{{printf .TASKLIB "auth"}}', dir: . }
  local:    { taskfile: '{{printf .TASKLIB "runtime/orbstack"}}', dir: . }
tasks: {}
YAML
# python rather than sed: the substitution is literal, so a tag
# carrying a `|`, a `&` or a backslash cannot rewrite the expression
# or leak into the shell.
python3 - "$REPO" "$TAG" <<'SUBST'
import sys, pathlib
p = pathlib.Path("Taskfile.yaml")
p.write_text(p.read_text().replace("OWNER_REPO", sys.argv[1]).replace("TAGVALUE", sys.argv[2]))
SUBST

# --yes accepts the first-fetch trust prompt; unattended, that prompt
# is a hang rather than a question.
task --yes --list-all > /dev/null
version=$(task --yes release:version)
case "$version" in
  9.9.9-dev.*) echo "✔ the published tag includes and resolves ($version)" ;;
  *) echo "✖ expected a 9.9.9 base, got $version" >&2; exit 1 ;;
esac
