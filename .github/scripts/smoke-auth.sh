#!/usr/bin/env bash
# Verify: auth passes its flags through and refuses a TTL that is not a number
set -euo pipefail
W="$RUNNER_TEMP/authgate"
mkdir -p "$W/shims"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/argv"\ncat >/dev/null\n' "$W" > "$W/shims/step"
chmod +x "$W/shims/step"
cd "$W"
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  auth: { taskfile: '$GITHUB_WORKSPACE/taskfiles/auth', dir: . }
tasks: {}
YAML
export PATH="$W/shims:$PATH"

task auth:mint-token JWT_TTL_SECONDS=60 STEP_FLAGS='--no-password --insecure'
for flag in --no-password --insecure; do
  grep -qx -- "$flag" argv || { echo "✖ STEP_FLAGS did not arrive as flags" >&2; cat argv >&2; exit 1; }
done
echo "✔ auth passes STEP_FLAGS through as flags"

# shellcheck disable=SC2016 # the $(...) is the payload, passed literally
if task auth:mint-token 'JWT_TTL_SECONDS=0 + $(touch substituted)' 2> ttl.err; then
  echo "✖ auth minted with a TTL that is not a number" >&2; exit 1
fi
test ! -e substituted || { echo "✖ a command substitution in the TTL ran" >&2; exit 1; }
grep -q 'must be a whole number' ttl.err
echo "✔ auth refuses a TTL that is not a number, without running it"
