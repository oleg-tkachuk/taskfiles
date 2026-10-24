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

# trivy: one --skip-dirs per listed directory, each a single argument.
shim trivy 'printf "[%s]" "$@" >> "$CALLS"; printf "\n" >> "$CALLS"'
consumer security security
reset_calls
run_task security:trivy
expect_status ok "trivy: runs with the default skip list"
expect_call "[--skip-dirs][.claude][--exit-code][1][.]" "trivy: skips .claude by default"
consumer security security "{ TRIVY_SKIP_DIRS: [.claude, 'third party'] }"
reset_calls
run_task security:trivy
expect_call "[--skip-dirs][.claude][--skip-dirs][third party][--exit-code][1][.]" "trivy: each listed directory is one --skip-dirs argument"
expect_call "[config][--exit-code][0][--quiet][--skip-dirs][.claude][--skip-dirs][third party]" "trivy: config skips the same directories"

# The gate's --exit-code comes last, where trivy's last-flag-wins parsing
# keeps it: a consumer's TRIVY_FLAGS cannot switch the gate off.
consumer security security "{ TRIVY_FLAGS: '--exit-code 0' }"
reset_calls
run_task security:trivy
expect_call "[--exit-code][0][--exit-code][1][.]" "trivy: TRIVY_FLAGS cannot override the gate's exit code"

# dockerfile: discovered when unset, linted exactly as named when set, and a
# named file that does not exist is an error — a typo must not lint nothing.
shim hadolint ''
consumer security security
reset_calls
run_task security:dockerfile
expect_status ok "dockerfile: a repository with no Dockerfile passes"
expect_output "no Dockerfile in this repository" "dockerfile: says there was nothing to lint"

mkdir -p "$CONSUMER/docker"
printf 'FROM scratch\n' > "$CONSUMER/docker/Dockerfile"
reset_calls
run_task security:dockerfile
expect_status ok "dockerfile: a discovered Dockerfile is linted"
expect_call "hadolint --failure-threshold error ./docker/Dockerfile" "dockerfile: hadolint runs on the discovered file"

consumer security security "{ DOCKERFILES: [docker/Dockerfile, docker/Dockerfil] }"
reset_calls
run_task security:dockerfile
expect_status fail "dockerfile: a named Dockerfile that does not exist fails"
expect_output "DOCKERFILES names docker/Dockerfil, which does not exist" "dockerfile: the missing file is named"
rm -rf "$CONSUMER/docker"

finish
