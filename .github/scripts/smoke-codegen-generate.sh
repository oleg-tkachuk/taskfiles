#!/usr/bin/env bash
# Verify: codegen actually generates
set -euo pipefail
test ! -f generated.go
task codegen:generate
test -f generated.go
grep -q 'const Generated = true' generated.go
echo "✔ codegen:generate wrote the file its directive asks for"
