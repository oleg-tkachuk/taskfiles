#!/usr/bin/env bash
# Verify: sealed-secrets passes the context and paths as data
set -euo pipefail
W="$RUNNER_TEMP/sealgate"
mkdir -p "$W/shims"
# shellcheck disable=SC2016 # the shims' own $@, written literally
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/argv"\necho "kind: Secret"\n' "$W" > "$W/shims/kubectl"
printf '#!/bin/sh\ncat\n' > "$W/shims/kubeseal"
chmod +x "$W/shims/kubectl" "$W/shims/kubeseal"
cd "$W"
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  ss: { taskfile: '$GITHUB_WORKSPACE/taskfiles/sealed-secrets', dir: . }
tasks: {}
YAML
# shellcheck disable=SC2016 # the $(...) is the payload, passed literally
PATH="$W/shims:$PATH" task ss:seal:literals name=app namespace=prod 'literals=A=1 B=two' \
  'output=out dir/app.yaml' 'K8S_CONTEXT=dev$(touch substituted)'
test ! -e substituted || { echo "✖ a command substitution in K8S_CONTEXT ran" >&2; exit 1; }
test -f 'out dir/app.yaml' || { echo "✖ the output path with a space was not honoured" >&2; exit 1; }
for arg in --from-literal=A=1 --from-literal=B=two; do
  grep -qx -- "$arg" argv || { echo "✖ kubectl did not get $arg" >&2; cat argv >&2; exit 1; }
done
echo "✔ sealed-secrets passes the context and paths as data"
