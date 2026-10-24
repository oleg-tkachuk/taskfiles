#!/usr/bin/env bash
# python/poetry and python/uv: install skips while the manifests are unchanged
# and the environment is there, and runs again once the environment is gone.
source "$(dirname "$0")/lib.sh"

# uv sync builds .venv in the project, as uv does. poetry keeps its venv
# outside the project by default, so the fake keeps it in $WORK and answers
# `env info --path` as poetry does: exit 1 when there is none.
shim uv '[ "$1" = sync ] && mkdir -p .venv; exit 0'
shim poetry '
case "$*" in
  install*) mkdir -p "$WORK/poetry-venv" ;;
  "env info --path") [ -d "$WORK/poetry-venv" ] && echo "$WORK/poetry-venv" ;;
esac'
export WORK

for case in "uv|uv sync|$CONSUMER/.venv" "poetry|poetry install|$WORK/poetry-venv"; do
  IFS="|" read -r variant call venv <<< "$case"
  consumer python "python/$variant"
  rm -rf "$CONSUMER/.task" "$venv"
  touch "$CONSUMER/pyproject.toml" "$CONSUMER/uv.lock" "$CONSUMER/poetry.lock"

  run_task python:install
  reset_calls
  run_task python:install
  expect_status ok "$variant: a second install runs"
  refute_call "$call" "$variant: a second install with the environment in place is skipped"

  rm -rf "$venv"
  reset_calls
  run_task python:install
  expect_status ok "$variant: an install after the environment was removed runs"
  expect_call "$call" "$variant: a removed environment is built again"
done

finish
