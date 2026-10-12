#!/usr/bin/env bash
# python/uv: every sync builds the venv on the pinned interpreter.
source "$(dirname "$0")/lib.sh"

shim uv 'exit 0'
consumer python python/uv '{ PY: "3.12" }'
touch "$CONSUMER/pyproject.toml" "$CONSUMER/uv.lock"

run_task python:deps:update
expect_status ok "deps:update: bumps the lock"
expect_call "uv lock --upgrade" "deps:update: upgrades the lock"
expect_call "uv sync --group dev --python 3.12" "deps:update: re-syncs on the pinned interpreter"

finish
