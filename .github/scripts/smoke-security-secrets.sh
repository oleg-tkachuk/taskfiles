#!/usr/bin/env bash
# Verify: the secrets gate asks gitleaks to say where, with values redacted
set -euo pipefail
W="$RUNNER_TEMP/secretsgate"
mkdir -p "$W/shims"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/argv"\nexit 0\n' "$W" > "$W/shims/gitleaks"
chmod +x "$W/shims/gitleaks"
cd "$W"
git init -q . && git config user.email ci@example.com && git config user.name CI
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  sec: { taskfile: '$GITHUB_WORKSPACE/taskfiles/security', dir: . }
tasks: {}
YAML
git add -A && git commit -qm seed
PATH="$W/shims:$PATH" task sec:secrets

grep -qx -- '--redact' argv || { echo "✖ gitleaks was not asked to redact" >&2; cat argv >&2; exit 1; }
grep -qx -- '-v' argv       || { echo "✖ gitleaks was not asked to report where" >&2; cat argv >&2; exit 1; }
echo "✔ the secrets gate passes both --redact and -v"
