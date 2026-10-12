#!/usr/bin/env bash
# python/uv: every sync builds the venv on the pinned interpreter, and doctor
# runs with no interpreter pinned at all.
source "$(dirname "$0")/lib.sh"

shim uv 'exit 0'
consumer python python/uv '{ PY: "3.12" }'
touch "$CONSUMER/pyproject.toml" "$CONSUMER/uv.lock"

run_task python:deps:update
expect_status ok "deps:update: bumps the lock"
expect_call "uv lock --upgrade" "deps:update: upgrades the lock"
expect_call "uv sync --group dev --python 3.12" "deps:update: re-syncs on the pinned interpreter"

# PY unset is a supported answer: uv picks the interpreter itself.
consumer python python/uv
run_task python:doctor
expect_output "interpreter: uv's choice (PY unset)" "doctor: runs and says so when PY is unset"
refute_output "template:" "doctor: an unset PY is not a template error"

finish
