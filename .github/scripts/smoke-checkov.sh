#!/usr/bin/env bash
# Verify: checkov passes its flags through and treats the version as data
set -euo pipefail
W="$RUNNER_TEMP/checkovgate"
mkdir -p "$W/shims"
# shellcheck disable=SC2016 # the shim's own $1 and $@, written literally
printf '#!/bin/sh\ncase "$1" in --version) echo 3.3.27; exit 0;; esac\nprintf "%%s\\n" "$@" > "%s/argv"\n' "$W" > "$W/shims/checkov"
chmod +x "$W/shims/checkov"
cd "$W"
printf 'directory: [.]\n' > .checkov.yaml
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  ckv: { taskfile: '$GITHUB_WORKSPACE/taskfiles/checkov', dir: ., vars: { CHECKOV_FLAGS: '--quiet --skip-download' } }
tasks: {}
YAML
export PATH="$W/shims:$PATH"

task ckv:scan
for flag in --quiet --skip-download; do
  grep -qx -- "$flag" argv || { echo "✖ CHECKOV_FLAGS did not arrive as flags" >&2; cat argv >&2; exit 1; }
done
echo "✔ checkov passes CHECKOV_FLAGS through as flags"

# shellcheck disable=SC2016 # the $(...) is the payload, passed literally
task ckv:scan 'CHECKOV_VERSION=$(touch substituted)' >/dev/null 2>&1 || true
test ! -e substituted || { echo "✖ a command substitution in CHECKOV_VERSION ran" >&2; exit 1; }
echo "✔ checkov treats CHECKOV_VERSION as data"
