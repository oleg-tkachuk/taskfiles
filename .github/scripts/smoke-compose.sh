#!/usr/bin/env bash
# Verify: compose splits the engine and keeps the file whole
set -euo pipefail
W="$RUNNER_TEMP/composegate"
mkdir -p "$W/shims"
# shellcheck disable=SC2016 # the shim's own $@, written literally
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/argv"\n' "$W" > "$W/shims/podman"
chmod +x "$W/shims/podman"
cd "$W"
touch 'my compose.yaml'
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  cmp: { taskfile: '$GITHUB_WORKSPACE/taskfiles/compose', dir: ., vars: { COMPOSE_ENGINE: 'podman compose', COMPOSE_FILE: 'my compose.yaml' } }
tasks: {}
YAML
PATH="$W/shims:$PATH" task cmp:logs SERVICE=web
[ "$(head -3 argv | tr '\n' '|')" = 'compose|-f|my compose.yaml|' ] || { echo "✖ the engine or the file did not arrive as meant" >&2; cat argv >&2; exit 1; }
grep -qx web argv || { echo "✖ SERVICE did not arrive" >&2; cat argv >&2; exit 1; }
echo "✔ compose splits the engine and keeps the file whole"
