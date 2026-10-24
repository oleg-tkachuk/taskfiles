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
refute_output ":443" "registry:check: the refusal names no port the registry was never asked on"

# A plain-HTTP registry, as the default localhost:5000 one is, answers too.
shim curl 'case "$*" in *https://*) printf 000 ;; *) printf 200 ;; esac'
run_task mono:registry:check
expect_status ok "registry:check: a registry answering over plain http is reachable"

# ─── doctor: the shared vars pool ─────────────────────────────────────────────
# A root Taskfile that includes its components puts all their top-level vars in
# one pool: a name one declares is what the others read, and which of two
# declarations wins is not stable. A name every component declares is safe.
# pool_root <c's Taskfile body> — a root including this module and three
# components; a declares DOCKERFILE and PORT, b declares PORT.
pool_root() {
  mkdir -p "$CONSUMER/a" "$CONSUMER/b" "$CONSUMER/c"
  printf 'version: "3"\nvars:\n  DOCKERFILE: ./deploy/Dockerfile\n  PORT: "8080"\n' > "$CONSUMER/a/Taskfile.yaml"
  printf 'version: "3"\nvars:\n  PORT: "8081"\n' > "$CONSUMER/b/Taskfile.yaml"
  printf '%s\n' "$1" > "$CONSUMER/c/Taskfile.yml"
  cat > "$CONSUMER/Taskfile.yaml" <<YAML
version: "3"
silent: true
includes:
  mono: { taskfile: '$LIB_ROOT/monorepo', dir: ., vars: { COMPONENTS: [a, b, c] } }
  a: { taskfile: ./a, dir: ./a }
  b: { taskfile: ./b/Taskfile.yaml, dir: ./b }
  c: ./c
YAML
}

pool_root 'version: "3"
vars:
  PORT: "8082"'
run_task mono:doctor
expect_status ok "doctor: a name only some components declare is a warning, not a failure"
expect_output "DOCKERFILE is declared at the top level of a only" "doctor: names the input and who declares it"
refute_output "PORT is declared" "doctor: a name every component declares is not reported"
refute_output "_MONO_" "doctor: the library module's own vars are not components'"

pool_root 'version: "3"
vars:
  DOCKERFILE: ./Dockerfile
  PORT: "8082"'
printf 'version: "3"\nvars:\n  DOCKERFILE: ./Dockerfile\n  PORT: "8081"\n' > "$CONSUMER/b/Taskfile.yaml"
run_task mono:doctor
expect_output "every top-level var is declared by every component" "doctor: a pool every component fills says so"

# Without yq the check cannot read the includes, and says so.
shim yq 'exit 1'
run_task mono:doctor
expect_status ok "doctor: no yq is a skipped check, not a failure"
expect_output "yq absent" "doctor: says the shared-vars check was skipped"
rm -f "$BIN/yq"
rm -rf "$CONSUMER/a" "$CONSUMER/b" "$CONSUMER/c"

finish
