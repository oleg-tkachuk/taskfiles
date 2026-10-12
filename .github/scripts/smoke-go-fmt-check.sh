#!/usr/bin/env bash
# Verify: go:fmt:check catches what go:fmt would rewrite
set -euo pipefail
printf 'package smoke\nfunc   Bad ( )   {}\n' > badfmt.go
if task go:fmt:check; then
  echo "✖ go:fmt:check passed on a file gofmt -l would list" >&2
  exit 1
fi
rm badfmt.go
task go:fmt:check
echo "✔ go:fmt:check fails on unformatted code and passes on clean code"
