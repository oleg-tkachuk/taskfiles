#!/usr/bin/env bash
# Verify: python passes each source dir and the typecheck module as data
set -euo pipefail
W="$RUNNER_TEMP/pythongate"
mkdir -p "$W/shims" "$W/src" "$W/tests"
# shellcheck disable=SC2016 # the shim's own $1 and $@, written literally
printf '#!/bin/sh\ncase "$1" in --version) echo "uv 0.13.0"; exit 0;; esac\nprintf "%%s|" "$@" >> "%s/calls"; printf "\\n" >> "%s/calls"\n' "$W" "$W" > "$W/shims/uv"
chmod +x "$W/shims/uv"
cd "$W"
touch pyproject.toml uv.lock
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  py: { taskfile: '$GITHUB_WORKSPACE/taskfiles/python/uv', dir: ., vars: { PY_SRC: 'src tests', TYPECHECK_MODULE: 'mypy' } }
tasks: {}
YAML
export PATH="$W/shims:$PATH"
# shellcheck disable=SC2016 # the $(...) is the payload, passed literally
task py:doctor 'PY=py$(touch substituted)' >/dev/null 2>&1 || true
test ! -e substituted || { echo "✖ a command substitution in PY ran" >&2; exit 1; }
task py:typecheck
grep -qxF 'run|python|-c|import importlib.util, sys; sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else int(sys.argv[2]))|mypy|3|' calls || { echo "✖ the typecheck module did not arrive as an argument" >&2; cat calls >&2; exit 1; }
grep -qxF 'run|mypy|src|tests|' calls || { echo "✖ PY_SRC did not arrive as one argument per directory" >&2; cat calls >&2; exit 1; }
echo "✔ python passes each source dir and the typecheck module as data"
