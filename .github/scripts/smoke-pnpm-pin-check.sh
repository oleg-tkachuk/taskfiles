#!/usr/bin/env bash
# Verify: pnpm:pin:check catches a pnpm shadowing the shim
set -euo pipefail
PIN=12.7.0
SHADOW_MSG="is not corepack's shim"
W="$RUNNER_TEMP/pnpm-shadow"
mkdir -p "$W/app" "$W/standalone" "$W/shims"
command -v corepack >/dev/null || { echo "✖ this runner's Node ships no corepack" >&2; exit 1; }
# corepack's own download of the pin, run from its cache rather than
# through the shim, is a standalone pnpm without npm installing one.
export COREPACK_HOME="$W/corepack"
corepack install -g "pnpm@$PIN"
standalone="$COREPACK_HOME/v1/pnpm/$PIN/pnpm"
test -x "$standalone" || { echo "✖ corepack's cache no longer keeps pnpm at $standalone" >&2; exit 1; }
# A wrapper, not a symlink: that launcher finds its own directory from
# $0, and through a symlink found on PATH it looks in the wrong place.
printf '#!/bin/sh\nexec "%s" "$@"\n' "$standalone" > "$W/standalone/pnpm"
chmod +x "$W/standalone/pnpm"
corepack enable --install-directory "$W/shims" pnpm
cd "$W"
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  pnpm: { taskfile: '$GITHUB_WORKSPACE/taskfiles/pnpm', dir: ., vars: { PNPM_APPS: ["app"] } }
YAML
printf '{ "name": "shadow", "private": true, "packageManager": "pnpm@%s" }\n' "$PIN" > app/package.json

if PATH="$W/standalone:$W/shims:$PATH" task pnpm:pin:check 2> shadowed.err; then
  echo "✖ pin:check passed with a standalone pnpm ahead of the shim" >&2
  exit 1
fi
grep -q "$SHADOW_MSG" shadowed.err || { cat shadowed.err >&2; echo "✖ pin:check failed, but not on the shadowing" >&2; exit 1; }
PATH="$W/shims:$W/standalone:$PATH" task pnpm:pin:check
echo "✔ pin:check fails on a shadowing pnpm and passes with the shim first"
