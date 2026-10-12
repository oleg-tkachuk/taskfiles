#!/usr/bin/env bash
# Verify: helm passes the context and namespace as single arguments
set -euo pipefail
W="$RUNNER_TEMP/helmgate"
mkdir -p "$W/shims"
printf '#!/bin/sh\nexit 0\n' > "$W/shims/kubectl"
# shellcheck disable=SC2016 # the shim's own $@, written literally
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/argv"\n' "$W" > "$W/shims/helm"
chmod +x "$W/shims/kubectl" "$W/shims/helm"
cd "$W"
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  helm: { taskfile: '$GITHUB_WORKSPACE/taskfiles/helm', dir: . }
tasks: {}
YAML
# shellcheck disable=SC2016 # the $(...) is the payload, passed literally
PATH="$W/shims:$PATH" task helm:list 'K8S_CONTEXT=dev$(touch substituted)' 'HELM_NS=my ns'
test ! -e substituted || { echo "✖ a command substitution in K8S_CONTEXT ran" >&2; exit 1; }
# shellcheck disable=SC2016 # matched literally, as it must arrive
grep -qxF 'dev$(touch substituted)' argv || { echo "✖ the context did not arrive as one argument" >&2; cat argv >&2; exit 1; }
grep -qx 'my ns' argv || { echo "✖ the namespace did not arrive as one argument" >&2; cat argv >&2; exit 1; }
echo "✔ helm passes the context and namespace as single arguments"
