#!/usr/bin/env bash
# Verify: pnpm:pin:update survives a postinstall that calls pnpm
set -euo pipefail
PIN_FROM=12.4.0
PIN_TO=12.7.0
MARKER=postinstall-ran.txt
W="$RUNNER_TEMP/pnpm-smoke"
mkdir -p "$W/app" "$W/standalone" "$W/shims"
command -v corepack >/dev/null || { echo "✖ this runner's Node ships no corepack" >&2; exit 1; }
# The standalone pnpm is corepack's own download of $PIN_FROM, run
# straight from its cache rather than through the shim - the same
# binary, minus the shim, which is all "standalone" means here.
export COREPACK_HOME="$W/corepack"
corepack install -g "pnpm@$PIN_FROM"
standalone="$COREPACK_HOME/v1/pnpm/$PIN_FROM/pnpm"
test -x "$standalone" || { echo "✖ corepack's cache no longer keeps pnpm at $standalone" >&2; exit 1; }
# A wrapper, not a symlink: that launcher finds its own directory from
# $0, and through a symlink found on PATH it looks in the wrong place.
printf '#!/bin/sh\nexec "%s" "$@"\n' "$standalone" > "$W/standalone/pnpm"
chmod +x "$W/standalone/pnpm"
corepack enable --install-directory "$W/shims" pnpm
export PATH="$W/standalone:$W/shims:$PATH"
cd "$W"
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  pnpm: { taskfile: '$GITHUB_WORKSPACE/taskfiles/pnpm', dir: ., vars: { PNPM_APPS: ["app"] } }
YAML
cat > app/package.json <<JSON
{ "name": "smoke", "private": true, "packageManager": "pnpm@$PIN_FROM",
  "scripts": { "postinstall": "pnpm --version > $MARKER" } }
JSON
task pnpm:pin:update:major -- "$PIN_TO"
pm=$(node -p "require('./app/package.json').packageManager")
case "$pm" in
  pnpm@"$PIN_TO"+sha512.*) ;;
  *) echo "✖ packageManager is $pm, want pnpm@$PIN_TO with its hash" >&2; exit 1 ;;
esac
test -f app/pnpm-lock.yaml || { echo "✖ pin:update wrote no lockfile" >&2; exit 1; }
ran=$(cat "app/$MARKER" 2>/dev/null || true)
if [ "$ran" != "$PIN_TO" ]; then
  echo "✖ postinstall ran as '${ran:-nothing}', want $PIN_TO" >&2
  exit 1
fi
echo "✔ pin:update moved the pin and ran postinstall on $PIN_TO"
