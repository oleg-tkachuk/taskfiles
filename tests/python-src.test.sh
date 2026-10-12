#!/usr/bin/env bash
# python/poetry and python/uv: PY_SRC is a list of directories, and each one
# reaches the tool as its own argument, as data.
source "$(dirname "$0")/lib.sh"

# Logs argv one bracket per argument, so one argument and two look different.
# The typecheck probe answers "installed", so typecheck runs.
# shellcheck disable=SC2016 # the shim's own $@, written literally
runner='printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"
case "$1" in --version) echo "1.0.0" ;; esac
exit 0'
shim uv "$runner"
shim poetry "$runner"

mkdir -p "$CONSUMER/src" "$CONSUMER/tests"
touch "$CONSUMER/pyproject.toml" "$CONSUMER/uv.lock" "$CONSUMER/poetry.lock"

for variant in uv poetry; do
  consumer python "python/$variant" '{ PY_SRC: "src  tests" }'

  reset_calls
  run_task python:lint
  expect_status ok "$variant: lint runs over several directories"
  expect_call "[run][ruff][check][src][tests]" "$variant: lint gets each directory as its own argument"

  reset_calls
  run_task python:fmt
  expect_call "[run][ruff][format][src][tests]" "$variant: fmt gets each directory as its own argument"

  reset_calls
  run_task python:typecheck
  expect_call "[run][mypy][src][tests]" "$variant: typecheck gets each directory as its own argument"

  consumer python "python/$variant" '{ PY_SRC: "src missing" }'
  run_task python:doctor
  expect_output "PY_SRC missing is not a directory" "$variant: doctor names the directory that is missing"
  refute_output "PY_SRC src is not a directory" "$variant: doctor does not flag a directory that is there"

  pwned="$WORK/pwned-$variant"
  consumer python "python/$variant" "{ PY_SRC: 'src \$(touch\${IFS}$pwned)' }"
  reset_calls
  run_task python:lint
  if [ -e "$pwned" ]; then fail "$variant: a \$( ) in PY_SRC ran"; else pass "$variant: a \$( ) in PY_SRC does not run"; fi
  expect_call "[src][\$(touch\${IFS}$pwned)]" "$variant: PY_SRC reaches the tool as data"
done

finish
