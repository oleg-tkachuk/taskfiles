#!/usr/bin/env bash
# monorepo: TARGET runs in every component, and a fan-out that cannot run —
# no components, an empty TARGET, a component that is not one — is refused
# rather than passing or recursing into the root Taskfile.
source "$(dirname "$0")/lib.sh"

# Two components; each records which task ran where.
for c in api web; do
  mkdir -p "$CONSUMER/$c"
  cat > "$CONSUMER/$c/Taskfile.yaml" <<YAML
version: "3"
silent: true
tasks:
  test: printf '%s\n' "ran test in $c" >> "$CALLS"
YAML
done

consumer mono monorepo '{ COMPONENTS: [api, web] }'
run_task mono:test
expect_status ok "each: runs in every component"
expect_call "ran test in api" "each: runs TARGET in the first component"
expect_call "ran test in web" "each: runs TARGET in the second component"

reset_calls
run_task mono:each TARGET=
expect_status fail "each: an empty TARGET is refused"
refute_call "ran test" "each: nothing runs on an empty TARGET"

consumer mono monorepo '{ COMPONENTS: [] }'
run_task mono:test
expect_status fail "each: an empty COMPONENTS is refused"
expect_output "COMPONENTS is empty" "each: says COMPONENTS is empty"

# A typo must not fall back to the parent directory and recurse into the root.
consumer mono monorepo '{ COMPONENTS: [api, wbe] }'
reset_calls
run_task mono:test
expect_status fail "each: a component that is not a directory is refused"
expect_output "wbe(no such directory)" "each: names the component that is not there"
refute_call "ran test" "each: nothing runs when a component is missing"

mkdir -p "$CONSUMER/docs"
consumer mono monorepo '{ COMPONENTS: [api, docs] }'
run_task mono:test
expect_status fail "each: a directory with no Taskfile is refused"
expect_output "docs(no Taskfile)" "each: names the directory with no Taskfile"

# registry:check: 200, 401 and 403 mean the registry answered.
consumer mono monorepo '{ COMPONENTS: [api] }'
for code in 200 401 403; do
  shim curl "printf $code"
  run_task mono:registry:check
  expect_status ok "registry:check: $code is reachable"
done
shim curl 'printf 000'
run_task mono:registry:check
expect_status fail "registry:check: no answer is unreachable"

finish
