#!/usr/bin/env bash
# Verify: runtime install passes every value as one argument
set -euo pipefail
W="$RUNNER_TEMP/runtimegate"
mkdir -p "$W/shims"
# shellcheck disable=SC2016 # the shims' own $1 and $@, written literally
printf '#!/bin/sh\ncase "$1" in get) echo kind;; esac\nexit 0\n' > "$W/shims/kind"
# shellcheck disable=SC2016 # the shim's own $@, written literally
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/argv"\n' "$W" > "$W/shims/helm"
chmod +x "$W/shims/kind" "$W/shims/helm"
cd "$W"
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  rt: { taskfile: '$GITHUB_WORKSPACE/taskfiles/runtime/kind', dir: . }
tasks: {}
YAML
# shellcheck disable=SC2016 # the $(...) is the payload, passed literally
PATH="$W/shims:$PATH" task rt:install 'PROJECT_NAME=svc$(touch substituted)' 'K8S_NAMESPACE=my ns' \
  'VALUES=my values.yaml' 'HELM_UPGRADE_FLAGS=--wait --atomic' _REL_IMAGE=img _REL_VERSION=1.2.3
test ! -e substituted || { echo "✖ a command substitution in PROJECT_NAME ran" >&2; exit 1; }
for arg in 'my ns' 'my values.yaml' --wait --atomic 'image.tag=1.2.3'; do
  grep -qxF -- "$arg" argv || { echo "✖ helm did not get '$arg' as one argument" >&2; cat argv >&2; exit 1; }
done
echo "✔ runtime install passes every value as one argument"
