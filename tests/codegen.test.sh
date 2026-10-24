#!/usr/bin/env bash
# codegen: GOWORK is off unless a consumer names "auto" — an empty value cannot
# opt in, `default` reads it as unset.
source "$(dirname "$0")/lib.sh"

shim go 'printf "go GOWORK=[%s]\n" "${GOWORK-unset}" >> "$CALLS"'
# _normalise formats what generation wrote; nothing here needs formatting.
shim goimports ':'
shim gofmt ':'

consumer codegen codegen
printf 'module example.com/x\n' > "$CONSUMER/go.mod"

for case in "default|off|" "auto||GOWORK=auto" "empty|off|GOWORK="; do
  IFS="|" read -r label expected arg <<< "$case"
  reset_calls
  run_task codegen:generate ${arg:+"$arg"}
  expect_status ok "generate: runs with GOWORK $label"
  expect_call "go GOWORK=[$expected]" "gowork: $label reaches go as [$expected]"
done

# ─── proto ────────────────────────────────────────────────────────────────────
# PROTO_PATH is shell by contract: a plugin out of a pnpm tree is named with
# the command that finds it.
shim buf 'printf "buf PATH=[%s]\n" "$PATH" >> "$CALLS"'
printf 'version: v2\n' > "$CONSUMER/buf.gen.yaml"

consumer codegen codegen "{ PROTO_PATH: '\$(printf %s /from-shell)' }"
reset_calls
run_task codegen:proto
expect_status ok "proto: runs with a PROTO_PATH that is a command substitution"
expect_call "buf PATH=[/from-shell:" "proto: PROTO_PATH is evaluated by the shell"

consumer codegen codegen "{ PROTO_PATH: '/a dir/bin' }"
reset_calls
run_task codegen:proto
expect_call "buf PATH=[/a dir/bin:" "proto: a PROTO_PATH with a space stays one entry"

consumer codegen codegen "{ PROTO_FORBID: 'gen api/gen' }"
run_task codegen:proto
expect_status ok "proto: runs when no forbidden path exists"
mkdir -p "$CONSUMER/api/gen"
reset_calls
run_task codegen:proto
expect_status fail "proto: refuses when one of several forbidden paths exists"
refute_call "buf " "proto: buf does not run beside a stray copy"
rm -rf "$CONSUMER/api"

finish
