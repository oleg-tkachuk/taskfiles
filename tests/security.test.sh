#!/usr/bin/env bash
# security: every GO_MODULES entry is scanned in its own directory, a
# directory that is not a Go module is skipped, and one that does not exist is
# an error — never created.
source "$(dirname "$0")/lib.sh"

shim govulncheck 'printf "govulncheck in %s\n" "$(basename "$PWD")" >> "$CALLS"'

mkdir -p "$CONSUMER/api" "$CONSUMER/docs"
printf 'module example.com/api\n' > "$CONSUMER/api/go.mod"

consumer security security "{ GO_MODULES: [api, docs] }"
run_task security:vuln
expect_status ok "vuln: a Go module and a plain directory pass"
expect_call "govulncheck in api" "vuln: the Go module is scanned in its own directory"
expect_output "docs is not a Go module — skipped" "vuln: a directory without go.mod is skipped"

consumer security security "{ GO_MODULES: [api, apii] }"
reset_calls
run_task security:vuln
expect_status fail "vuln: a GO_MODULES entry that does not exist fails"
expect_output "GO_MODULES names apii, which does not exist" "vuln: the missing entry is named"
if [ -e "$CONSUMER/apii" ]; then fail "vuln: the missing directory was created"; else pass "vuln: the missing directory is not created"; fi

finish
