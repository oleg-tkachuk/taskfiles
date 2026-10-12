#!/usr/bin/env bash
# python/poetry and python/uv: typecheck says when it skips, and an environment
# that cannot be asked is a failure rather than a skip.
source "$(dirname "$0")/lib.sh"

# FAKE_ENV: "absent" — the module is not installed; "broken" — the runner
# itself fails; anything else — installed. The probe exits with the code the
# task asked for when the module is absent, as Python would.
runner='
case "$*" in
  *"python -c "*)
    case "${FAKE_ENV:-}" in
      absent) eval "exit \${@: -1}" ;;
      broken) echo "error: no virtual environment" >&2; exit 2 ;;
      *) exit 0 ;;
    esac ;;
  *"run mypy"*) exit "${FAKE_MYPY_STATUS:-0}" ;;
esac
exit 0'
shim uv "$runner"
shim poetry "$runner"

for variant in uv poetry; do
  consumer python "python/$variant"
  touch "$CONSUMER/pyproject.toml" "$CONSUMER/uv.lock" "$CONSUMER/poetry.lock"

  export FAKE_ENV=absent
  reset_calls
  run_task python:typecheck
  expect_status ok "$variant: typecheck passes when mypy is not a dependency"
  expect_output "○" "$variant: typecheck says it skipped"
  refute_call "run mypy" "$variant: mypy is not run when it is not a dependency"

  export FAKE_ENV=broken
  reset_calls
  run_task python:typecheck
  expect_status fail "$variant: an environment that cannot be asked fails typecheck"
  refute_call "run mypy" "$variant: mypy is not run in a broken environment"

  export FAKE_ENV=installed
  reset_calls
  run_task python:typecheck
  expect_status ok "$variant: typecheck runs when mypy is a dependency"
  expect_call "run mypy src" "$variant: mypy runs over the source"

  export FAKE_MYPY_STATUS=1
  run_task python:typecheck
  expect_status fail "$variant: a type error fails typecheck"
  refute_output "types clean" "$variant: a type error is not reported clean"
  unset FAKE_ENV FAKE_MYPY_STATUS
done

finish
