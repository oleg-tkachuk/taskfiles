#!/usr/bin/env bash
# Verify: gosec runs the module's own tool before one on PATH
set -euo pipefail
W="$RUNNER_TEMP/gosec-tool"
mkdir -p "$W/fake/cmd/gosec" "$W/withtool" "$W/plain" "$W/shims"
cd "$W"
printf 'module example.com/fake\n\ngo 1.24\n' > fake/go.mod
printf 'package main\n\nimport (\n\t"os"\n\t"strings"\n)\n\nfunc main() { _ = os.WriteFile("argv", []byte("tool "+strings.Join(os.Args[1:], " ")), 0o644) }\n' > fake/cmd/gosec/main.go
printf 'module example.com/withtool\n\ngo 1.24\n\nrequire example.com/fake v0.0.0\n\nreplace example.com/fake => ../fake\n\ntool example.com/fake/cmd/gosec\n' > withtool/go.mod
printf 'module example.com/plain\n\ngo 1.24\n' > plain/go.mod
printf '#!/bin/sh\nprintf "path %%s" "$*" > argv\n' > shims/gosec
chmod +x shims/gosec
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  sec: { taskfile: '$GITHUB_WORKSPACE/taskfiles/security', dir: ., vars: { GO_MODULES: ["withtool", "plain"], GOSEC_FLAGS: "-quiet" } }
tasks: {}
YAML
PATH="$W/shims:$PATH" task sec:gosec

[ "$(cat withtool/argv)" = "tool -quiet ./..." ] || { echo "✖ the module's tool was not used" >&2; cat withtool/argv >&2; exit 1; }
[ "$(cat plain/argv)" = "path -quiet ./..." ]   || { echo "✖ PATH gosec was not the fallback" >&2; cat plain/argv >&2; exit 1; }

rm -f plain/argv
if NO_COLOR=1 task sec:gosec 2> missing.err; then
  echo "✖ gosec passed with no gosec for a module to run" >&2; exit 1
fi
grep -q 'go get -tool github.com/securego/gosec/v2/cmd/gosec' missing.err || { cat missing.err >&2; exit 1; }
echo "✔ gosec prefers the module's tool, falls back to PATH, and names go get -tool"
