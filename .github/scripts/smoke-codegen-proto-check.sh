#!/usr/bin/env bash
# Verify: proto:check derives what it watches, and refuses when it cannot
set -euo pipefail
W="$RUNNER_TEMP/protogate"
mkdir -p "$W/shims" "$W/gen/go"
# The shim stands in for buf: it writes what generation would, which
# is whatever canonical.go holds — the stub's "source" here. The
# gate regenerates and checks whether that changed the tree.
printf '#!/bin/sh\ncp "%s/canonical.go" "%s/gen/go/greet.pb.go"\n' "$W" "$W" > "$W/shims/buf"
chmod +x "$W/shims/buf"
cd "$W"
git init -q . && git config user.email ci@example.com && git config user.name CI
printf 'version: v2\nplugins:\n  - local: protoc-gen-go\n    out: gen/go\n' > buf.gen.yaml
printf 'package greetv1\n' > canonical.go
cp canonical.go gen/go/greet.pb.go
cat > Taskfile.yaml <<YAML
version: "3"
includes:
  cg:
    taskfile: '$GITHUB_WORKSPACE/taskfiles/codegen'
    dir: .
    vars: { PROJECT_NAME: gate, BUF_TEMPLATE: ["buf.gen.yaml"] }
tasks: {}
YAML
git add -A && git commit -qm "seed"
export PATH="$W/shims:$PATH"

task cg:proto:check | grep -q 'stubs match their sources'
echo "✔ proto:check passes on a tree whose stubs are committed"

# Pathspec magic carries a parenthesis, which the shell reads as
# syntax unless each pathspec is quoted; the gate died on it before
# comparing anything.
GLOB_SPEC=':(glob)gen/**'
task cg:proto:check PROTO_PATHSPEC="$GLOB_SPEC" | grep -q 'stubs match their sources'
printf 'package greetv1\n// drifted\n' > gen/go/greet.pb.go
if task cg:proto:check PROTO_PATHSPEC="$GLOB_SPEC" 2> glob.err; then
  echo "✖ proto:check passed a stale stub under a glob pathspec" >&2; exit 1
fi
grep -q 'stubs are stale' glob.err
git checkout -q -- gen/go
echo "✔ proto:check takes a pathspec with magic, and still sees drift through it"

# A quote in the pathspec is data, not shell: the gate reports the
# directory it cannot find instead of failing to parse the value.
if task cg:proto:check PROTO_PATHSPEC="gen/it's" > quote.out 2>&1; then
  echo "✖ proto:check passed a pathspec that names nothing" >&2; exit 1
fi
grep -q "gen/it's holds no tracked file" quote.out || { cat quote.out >&2; exit 1; }
echo "✔ proto:check reads a quote in its pathspec as data"

# An `out:` path is read from a file, so it is data too: a command
# substitution in it must never run.
PROBE="$W/substituted"
# shellcheck disable=SC2016 # the $(...) is the payload, written literally
printf 'version: v2\nplugins:\n  - local: protoc-gen-go\n    out: gen/$(touch %s)\n' "$PROBE" > buf.gen.yaml
task cg:proto:check > subst.out 2>&1 || true
test ! -e "$PROBE" || { echo "✖ proto:check ran a command substitution from an out: path" >&2; exit 1; }
git checkout -q -- buf.gen.yaml
echo "✔ proto:check never runs a command substitution from an out: path"

printf 'package greetv1\n// drifted\n' > gen/go/greet.pb.go
if task cg:proto:check 2> drift.err; then
  echo "✖ proto:check passed on a stale stub" >&2; exit 1
fi
grep -q 'stubs are stale' drift.err
echo "✔ proto:check fails when a stub no longer matches what generation writes"
git checkout -q -- gen/go

# A source change regenerated but not yet committed is a fresh tree:
# the gate runs before a commit, so it must pass here.
printf 'package greetv1\n// v2\n' > canonical.go
task cg:proto >/dev/null
task cg:proto:check | grep -q 'stubs match their sources'
echo "✔ proto:check passes a regenerated, uncommitted change"

# The same source change without regenerating is stale.
printf 'package greetv1\n// v3\n' > canonical.go
if task cg:proto:check 2> source.err; then
  echo "✖ proto:check passed a source change it was not regenerated for" >&2; exit 1
fi
grep -q 'stubs are stale' source.err
echo "✔ proto:check fails a source change that was not regenerated"
printf 'package greetv1\n' > canonical.go
git checkout -q -- gen/go

# `out:` inside a flow mapping: valid YAML, accepted by buf, invisible
# to a line parser. The gate must refuse, not report a clean tree.
printf 'version: v2\nplugins: [{local: protoc-gen-go, out: gen/go}]\n' > buf.gen.yaml
if task cg:proto:check 2> flow.err; then
  echo "✖ proto:check passed on a template it could not parse" >&2; exit 1
fi
grep -q 'no out: path in' flow.err
echo "✔ proto:check refuses a template whose out: it cannot read"

# `out: .` is legitimate — a plugin carrying the subdirectory in
# `module=` writes from the component root — and watching the root
# would report every unrelated change as a stale stub.
printf 'version: v2\nplugins:\n  - local: protoc-gen-go\n    out: .\n' > buf.gen.yaml
if task cg:proto:check 2> root.err; then
  echo "✖ proto:check watched the component root" >&2; exit 1
fi
grep -q 'writes to the component root' root.err
echo "✔ proto:check refuses a template that writes to the component root"

# Every target untracked is a gate that checks nothing, which must be
# an error rather than a pass.
if task cg:proto:check PROTO_PATHSPEC=gen/nothing 2> empty.err; then
  echo "✖ proto:check passed with nothing tracked to check" >&2; exit 1
fi
grep -q 'checks nothing' empty.err
echo "✔ proto:check refuses when no watched directory holds a tracked file"
