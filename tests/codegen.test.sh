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

finish
