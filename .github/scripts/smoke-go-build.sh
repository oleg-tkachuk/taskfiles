#!/usr/bin/env bash
# Verify: the go module compiles, tests and builds
set -euo pipefail
task go:fmt
task go:fmt:check
task go:compile
task go:test
task go:tidy
echo "✔ the go module's tasks run against a real module"
